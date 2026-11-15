import AppKit

/// The text view of a pane: read-only text on the row grid, drawn with TextKit 2.
///
/// Selection, copying, the find bar, input methods and VoiceOver come from `NSTextView`. The
/// view adds the row fills, the highlights and marks within lines and its size, all from the
/// grid rather than from TextKit, so that row *r* lies at the first screen line of its display
/// row times `rowHeight` in every pane; the rows behind a collapsed run take no room, except the
/// one of its bar. Its fragments draw the selection, translucent above the row fills (see
/// `RowLayoutFragment`).
final class PaneTextView: NSTextView {
  private(set) var theme = Theme()
  private(set) var content = PaneContent.empty
  private(set) var currentBlock: Int?
  var grid = RowGrid(text: "", tabWidth: 1)
  private(set) var displayRows = DisplayRows(runs: [], rowCount: 1) {
    didSet { contentStorage.hiddenRanges = hiddenRanges }
  }

  /// How the rows break into screen lines at the width of the text, or `nil` while lines do not
  /// wrap.
  private(set) var lineWrapping: RowWrapping?

  /// The rows that wrap at the width of this pane's own text.
  ///
  /// The pane shows each row as high as in the most wrapped of the panes it lines up with,
  /// which ``setWrappedRows(_:)`` gives it.
  private(set) var ownWrappedRows = WrappedRows.none

  /// The content storage, which the text view holds only weakly.
  let contentStorage = PaneContentStorage()

  /// The rows below the visible text whose paragraph elements are still to be discarded, once
  /// scrolling is at rest and the run loop is idle.
  var rowsToDiscard: Range<Int>?

  /// The farthest row that has been in view since discarding last finished: TextKit holds no
  /// elements far below it.
  var farthestRowShown = 0

  /// Whether the user is scrolling by hand, with the scroller or a gesture.
  var isLiveScrolling = false

  /// Fires once the visible text has stayed where it is for the rest interval.
  var scrollRestTimer: Timer?

  /// Whether a pass of discarding waits for the run loop to be idle.
  var isDiscardPassPending = false

  /// Learns about clicks on rows and supplies the context menu.
  weak var interaction: (any RowInteraction)?

  /// Whether a find action of the find bar or the Find menu is under way, whose result comes into
  /// view the way a jump does.
  var isPerformingFindAction = false

  /// The search over several panes that this view hands its find commands to, if it is among
  /// its sections.
  weak var search: PaneSearch?

  /// The matches of a search that the view marks, as ranges of its text, sorted and apart.
  var searchMatches: [Range<Int>] = [] {
    didSet {
      guard searchMatches != oldValue else { return }
      redraw(ranges: oldValue + searchMatches)
    }
  }

  /// Whether spaces, tabs and line endings show as symbols.
  var showsInvisibles = false {
    didSet {
      if showsInvisibles != oldValue {
        redraw(rows: 0..<grid.rowCount)
      }
    }
  }

  /// Supplies the changed runs within lines, asked once per block when it is first drawn.
  weak var highlightProvider: (any PaneHighlightProvider)? {
    didSet { reloadHighlights() }
  }

  private var highlightsByBlock: [Int: [Range<Int>]] = [:]

  /// Supplies the tokens of the lines, asked for each row as it is drawn.
  weak var syntaxProvider: (any PaneSyntaxProvider)? {
    didSet { syntaxDidChange(inRows: nil) }
  }

  /// The selection as the fragments last drew it.
  private var drawnSelection: [NSValue] = []

  /// The rows of lines too long to show whole that the pane shows whole all the same, because
  /// the insertion point or the selection lies in them, with the columns of the widest.
  var wholeRows = (rows: IndexSet(), columns: 0)

  /// The edits that the text is about to undergo, in order, which its changes are checked
  /// against.
  var announcements: [Announcement] = []

  /// The edits of the user that the text has undergone and that are reported once the text view
  /// has finished the change.
  var completedEdits: [Announcement] = []

  /// Whether the pane is putting new content into its text, a change that nobody announces.
  private(set) var isShowingContent = false

  /// The offsets of the previews, those next to each other joined, or `nil` until they are asked
  /// for after a change.
  var cachedPreviewSpans: [Range<Int>]?

  /// The version of the text, after whose changes fragments find their rows again.
  private let textVersion = TextVersion()

  /// Whether text has been given a color of its own since the pane last had neither previews
  /// nor a syntax provider.
  var hasColoredText = false

  /// The previews as the pane's owner gave them last, before edits moved them along with the
  /// text.
  private var givenPreviews: [PanePreview] = []

  /// The rows of each preview with its side, or `nil` until they are asked for after a change.
  var cachedPreviewRows: [(rows: Range<Int>, role: ColorRole)]?

  /// Creates an empty text view on TextKit 2.
  init() {
    let textLayoutManager = NSTextLayoutManager()
    contentStorage.addTextLayoutManager(textLayoutManager)
    let textContainer = NSTextContainer()
    textLayoutManager.textContainer = textContainer
    super.init(frame: .zero, textContainer: textContainer)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Sets up the view as a pane; called once, before any content is shown.
  func configure(theme: Theme) {
    isEditable = false
    isSelectable = true
    isRichText = false
    importsGraphics = false
    allowsUndo = false
    usesFindBar = true
    isIncrementalSearchingEnabled = true
    usesFontPanel = false
    usesRuler = false
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isAutomaticTextReplacementEnabled = false
    isAutomaticSpellingCorrectionEnabled = false
    isAutomaticLinkDetectionEnabled = false
    isAutomaticDataDetectionEnabled = false
    isAutomaticTextCompletionEnabled = false
    isContinuousSpellCheckingEnabled = false
    isGrammarCheckingEnabled = false
    smartInsertDeleteEnabled = false
    writingToolsBehavior = .none
    drawsBackground = true
    backgroundColor = Theme.backgroundColor
    isHorizontallyResizable = false
    isVerticallyResizable = false
    autoresizingMask = []
    textContainerInset = NSSize(width: Theme.textInset, height: 0)
    if let textContainer {
      textContainer.widthTracksTextView = false
      textContainer.heightTracksTextView = false
      textContainer.lineFragmentPadding = 0
      textContainer.size = CGSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
    textLayoutManager?.delegate = self
    textContentStorage?.delegate = self
    textStorage?.delegate = self
    NotificationCenter.default.addObserver(
      self, selector: #selector(willSwitchToLayoutManager(_:)),
      name: NSTextView.willSwitchToNSLayoutManagerNotification, object: self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionDidChange(_:)),
      name: NSTextView.didChangeSelectionNotification, object: self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(discardNextParagraphsWhenIdle(_:)),
      name: Self.idleToDiscardNotification, object: self)
    self.theme = theme
  }

  /// Shows `content` with `collapsedRuns`, drawn with `theme`.
  ///
  /// - Precondition: `content` has one line number per row, and the runs lie within its rows.
  func show(_ content: PaneContent, collapsedRuns: [CollapsedRun], theme: Theme) {
    let keepsText = (content.text as NSString).isEqual(to: string)
    // The rows of the same text are those the pane knows.
    let grid =
      keepsText && theme.tabWidth == self.theme.tabWidth
      ? self.grid : RowGrid(text: content.text, tabWidth: theme.tabWidth)
    precondition(
      content.lineNumbers.count == grid.rowCount,
      "\(content.lineNumbers.count) line numbers for \(grid.rowCount) rows")
    precondition(
      content.lineEndings.count == grid.rowCount,
      "\(content.lineEndings.count) line endings for \(grid.rowCount) rows")
    let previewsChanged = content.previews != self.content.previews
    givenPreviews = content.previews
    self.content = content
    self.theme = theme
    self.grid = grid
    if let lineWrapping {
      // The width of characters may have changed with the theme.
      self.lineWrapping = makeLineWrapping(width: lineWrapping.width)
    }
    ownWrappedRows = wrappedRows(in: 0..<grid.rowCount, of: content.text as NSString)
    // The pane lines the rows up with its neighbors once it has shown them.
    displayRows = DisplayRows(
      runs: collapsedRuns, rowCount: grid.rowCount, wrappedRows: ownWrappedRows)
    textVersion.increment()
    if let currentBlock, !content.blocks.indices.contains(currentBlock) {
      self.currentBlock = nil
    }
    highlightsByBlock.removeAll()
    cachedPreviewSpans = nil
    cachedPreviewRows = nil
    updateTextColorValidation()
    let attributes = textAttributes
    font = theme.font
    defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
    typingAttributes = attributes
    guard let textStorage else { return }
    isShowingContent = true
    defer { isShowingContent = false }
    if keepsText {
      // The same text with new rows and blocks: the selection and the scroll position stay.
      if previewsChanged {
        fadeAfterPreviewChange()
      }
      textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
      if let textLayoutManager {
        textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
        textLayoutManager.invalidateRenderingAttributes(for: textLayoutManager.documentRange)
        // Setting the attributes makes TextKit lay out every paragraph anew, which gives the
        // tokens their colors.
        applyTextColors(in: 0..<textStorage.length, syntaxIn: 0..<0)
      }
    } else {
      textStorage.setAttributedString(
        NSAttributedString(string: content.text, attributes: attributes))
      rowsToDiscard = nil
      farthestRowShown = 0
    }
  }

  /// Replaces the blocks and previews of the content, keeping its text, rows and line numbers,
  /// and draws again only the rows whose block or preview changed.
  ///
  /// - Precondition: The blocks are sorted, do not overlap and lie within the rows; the previews
  ///   are sorted, do not overlap and lie within the text.
  func setBlocks(_ blocks: [PaneBlock], previews: [PanePreview], rowTints: [Int: BlockStyle]) {
    precondition(
      (blocks.last?.rows.upperBound ?? 0) <= grid.rowCount,
      "Blocks reach beyond the \(grid.rowCount) rows")
    precondition(
      (previews.last?.range.upperBound ?? 0) <= grid.textLength,
      "Previews reach beyond the text of length \(grid.textLength)")
    precondition(
      rowTints.keys.allSatisfy { $0 < grid.rowCount },
      "Row tints reach beyond the \(grid.rowCount) rows")
    let oldBlocks = content.blocks
    let previewsChanged = previews != content.previews
    // Previews that an edit moved along with the text keep the look their fragments had where
    // they stood before, so their rows draw again although they are as the edit left them.
    let previewsMoved = previews != givenPreviews
    givenPreviews = previews
    var changedRows = previewsChanged ? previewRows().map(\.rows) : []
    changedRows += Set(rowTints.keys).union(content.rowTints.keys)
      .filter { rowTints[$0] != content.rowTints[$0] }.map { $0..<$0 + 1 }
    content.blocks = blocks
    content.previews = previews
    content.rowTints = rowTints
    if let currentBlock, !blocks.indices.contains(currentBlock) {
      self.currentBlock = nil
    }
    highlightsByBlock.removeAll()
    cachedPreviewSpans = nil
    cachedPreviewRows = nil
    if previewsChanged {
      fadeAfterPreviewChange()
      updateTextColorValidation()
    }
    if previewsChanged || previewsMoved {
      changedRows += previewRows().map(\.rows)
    }
    for index in 0..<max(oldBlocks.count, blocks.count) {
      let old = index < oldBlocks.count ? oldBlocks[index] : nil
      let new = index < blocks.count ? blocks[index] : nil
      guard old != new else { continue }
      changedRows += [old?.rows, new?.rows].compactMap { $0.map(drawnRows(of:)) }
    }
    // The row after a block draws the edge between them, whose color depends on both.
    for rows in changedRows where !rows.isEmpty {
      redraw(rows: (rows.lowerBound..<rows.upperBound + 1).clamped(to: 0..<grid.rowCount))
    }
  }

  /// Takes over a change of the text that replaced `range` by `length` code units and rewrote
  /// rows as `change` says, so that rows, blocks, previews and collapsed runs stay described until
  /// the pane's owner gives it the exact content.
  ///
  /// A collapsed run that the change reached into is expanded: its rows are no longer unchanged.
  func takeOver(_ change: RowChange, replacing range: Range<Int>, length: Int, text: String) {
    content.takeOver(change, replacing: range, length: length, text: text)
    // A line that is typed in stays whole until the selection says where it is now.
    var whole = IndexSet()
    for row in wholeRows.rows {
      if change.oldRows.contains(row) {
        whole.insert(integersIn: change.newRows)
      } else {
        whole.insert(change.newBoundary(of: row))
      }
    }
    wholeRows.rows = whole
    textVersion.increment()
    let runs = displayRows.runs.compactMap { run -> CollapsedRun? in
      guard !run.rows.overlaps(change.oldRows) else { return nil }
      let rows = change.newRows(of: run.rows)
      return rows.isEmpty ? nil : CollapsedRun(rows: rows)
    }
    let rewritten = wrappedRows(in: change.newRows, of: text as NSString).entries
    ownWrappedRows.takeOver(change, rewritten: rewritten)
    // The rows that the edit rewrote take their own lines until the panes line up again.
    var wrappedRows = displayRows.wrappedRows
    wrappedRows.takeOver(change, rewritten: rewritten)
    displayRows = DisplayRows(runs: runs, rowCount: grid.rowCount, wrappedRows: wrappedRows)
    highlightsByBlock.removeAll()
    cachedPreviewSpans = nil
    cachedPreviewRows = nil
    interaction?.textDidChange()
  }

  /// Hides `runs` of rows behind bars, each one row high, and lays out the text again.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows.
  func setCollapsedRuns(_ runs: [CollapsedRun]) {
    guard runs != displayRows.runs else { return }
    displayRows = DisplayRows(
      runs: runs, rowCount: grid.rowCount, wrappedRows: displayRows.wrappedRows)
    guard let textLayoutManager else { return }
    // Which paragraphs the layout manager enumerates changes with the runs.
    textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
    needsDisplay = true
    // A fragment that keeps its frame, such as the first of a run that started at the top,
    // would keep drawing as it did behind the bar.
    setNeedsDisplayOfFragments(in: bounds)
  }

  /// The text of the rows that the collapsed runs hide behind their first rows.
  private var hiddenRanges: [Range<Int>] {
    displayRows.runs.compactMap { run in
      guard run.rows.count > 1 else { return nil }
      let end =
        run.rows.upperBound < grid.rowCount
        ? grid.offsets(ofRow: run.rows.upperBound).lowerBound : grid.textLength
      return grid.offsets(ofRow: run.rows.lowerBound + 1).lowerBound..<end
    }
  }

  /// Wraps the lines at `width`, the width of the text area less its insets, or lets them run
  /// on without wrapping for `nil`, and returns whether the rows that wrap in this pane changed.
  ///
  /// The pane lays out its text again and finds the rows that wrap; it shows them once it is
  /// given the rows that wrap in the panes it lines up with too.
  @discardableResult
  func wrapLines(atWidth width: CGFloat?) -> Bool {
    guard width != lineWrapping?.width else { return false }
    lineWrapping = width.map(makeLineWrapping(width:))
    // TextKit lays out the whole text again for a container of another size.
    textContainer?.size = CGSize(
      width: width ?? CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    setNeedsDisplayOfFragments(in: bounds)
    let wrappedRows = wrappedRows(in: 0..<grid.rowCount, of: string as NSString)
    guard wrappedRows != ownWrappedRows else { return false }
    ownWrappedRows = wrappedRows
    return true
  }

  /// Shows each row as high as `wrappedRows` says, the rows that wrap in this pane or in a pane
  /// it lines up with, and returns whether any row changed its height.
  ///
  /// Rows that wrap less here than `wrappedRows` says keep a quiet fill below their text.
  @discardableResult
  func setWrappedRows(_ wrappedRows: WrappedRows) -> Bool {
    let wrappedRows = wrappedRows.clamped(toRowCount: grid.rowCount)
    guard let firstChange = wrappedRows.firstRow(differingFrom: displayRows.wrappedRows) else {
      return false
    }
    displayRows = DisplayRows(
      runs: displayRows.runs, rowCount: grid.rowCount, wrappedRows: wrappedRows)
    // The fragments find their frames from the rows. TextKit keeps the frames of the fragments it
    // has laid out, though, and finds the fragment at a place by them, so it would look for the
    // visible part among frames that no longer hold and show nothing there. The elements from the
    // first row that changed its height on are dropped, so that TextKit makes their fragments
    // anew, at the frames the rows have now, once it lays them out again.
    textVersion.increment()
    if firstChange < grid.rowCount {
      let start = grid.paragraphOffsets(ofRows: firstChange..<firstChange + 1).lowerBound
      contentStorage.discardElements(in: start..<grid.textLength)
    }
    if let textLayoutManager,
      let viewport = textLayoutManager.textViewportLayoutController.viewportRange
    {
      textLayoutManager.invalidateLayout(for: viewport)
    }
    needsDisplay = true
    setNeedsDisplayOfFragments(in: bounds)
    return true
  }

  /// Counts the screen lines of `row` of `text` again, after it changed between cut and whole.
  func rewrap(row: Int, of text: NSString) {
    let change = RowChange(oldRows: row..<row + 1, newRows: row..<row + 1)
    let rewritten = wrappedRows(in: row..<row + 1, of: text).entries
    ownWrappedRows.takeOver(change, rewritten: rewritten)
    var wrappedRows = displayRows.wrappedRows
    wrappedRows.takeOver(change, rewritten: rewritten)
    displayRows = DisplayRows(
      runs: displayRows.runs, rowCount: grid.rowCount, wrappedRows: wrappedRows)
  }

  /// The rows among `rows` of `text` that wrap at the width of the lines, none while lines do
  /// not wrap.
  private func wrappedRows(in rows: Range<Int>, of text: NSString) -> WrappedRows {
    guard let lineWrapping else { return .none }
    return WrappedRows(
      lineWrapping.wrappedRows(rows, of: text, grid: grid, wholeRows: wholeRows.rows))
  }

  private func makeLineWrapping(width: CGFloat) -> RowWrapping {
    RowWrapping(width: width, attributes: textAttributes, theme: theme)
  }

  /// Marks the block at `block` as the current one, or none.
  func setCurrentBlock(_ block: Int?) {
    guard block != currentBlock else { return }
    let previous = currentBlock
    currentBlock = block
    for index in [previous, block].compactMap(\.self) where content.blocks.indices.contains(index) {
      redraw(rows: drawnRows(of: content.blocks[index].rows))
    }
  }

  /// The rows that draw a block on `rows`: those rows, or for a block without rows that is
  /// marked, the row that draws its hairline.
  func drawnRows(of rows: Range<Int>) -> Range<Int> {
    guard rows.isEmpty, content.marksBlocksWithoutRows else { return rows }
    let row = content.hairlineRow(ofBoundary: rows.lowerBound)
    return row..<row + 1
  }

  /// The width that the widest row needs, known before TextKit lays it out, so that the scroll
  /// range does not grow while the user scrolls.
  var textWidth: CGFloat {
    (CGFloat(max(grid.widestRowColumns, wholeRows.columns)) * theme.characterWidth
      + 2 * Theme.textInset).rounded(.up)
  }

  /// The origin of the text, fixed by the inset.
  ///
  /// `NSTextView` would derive it from the extent of the laid-out text, and to find that, lay
  /// out the whole document whenever the view's geometry changes.
  override var textContainerOrigin: NSPoint {
    NSPoint(x: textContainerInset.width, y: textContainerInset.height)
  }

  /// The rectangle on screen of the characters in `range`, or of the insertion point for an
  /// empty range, which input methods put their candidates next to.
  ///
  /// The text view finds no rectangle for the insertion point on an empty last row, whose line
  /// the pane moved down to the row; the line's place gives it.
  override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?)
    -> NSRect
  {
    guard range.length == 0, grid.endsWithEmptyRow, range.location == grid.textLength,
      let manager = textLayoutManager,
      let location = manager.location(manager.documentRange.location, offsetBy: range.location)
    else { return super.firstRect(forCharacterRange: range, actualRange: actualRange) }
    var place: CGRect?
    manager.enumerateTextSegments(in: NSTextRange(location: location), type: .standard) {
      _, frame, _, _ in
      place = frame
      return false
    }
    guard let place, let window else {
      return super.firstRect(forCharacterRange: range, actualRange: actualRange)
    }
    actualRange?.pointee = range
    let inView = place.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    return window.convertToScreen(convert(inView, to: nil))
  }

  override func mouseDown(with event: NSEvent) {
    let row = row(at: convert(event.locationInWindow, from: nil))
    // The text view tracks the mouse until the button goes up.
    super.mouseDown(with: event)
    interaction?.rowWasClicked(row)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let interaction, interaction.suppliesMenus else { return super.menu(for: event) }
    return interaction.menu(forRow: row(at: convert(event.locationInWindow, from: nil)))
  }

  /// The row at `point` of the view, the nearest one beyond the text; on a bar, the first row
  /// that it hides.
  private func row(at point: CGPoint) -> Int {
    let line = Int((point.y / theme.rowHeight).rounded(.down))
    return displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: line))
  }

  override func becomeFirstResponder() -> Bool {
    defer {
      redraw(selections: selectedRanges)
      interaction?.selectionDidChange()
    }
    return super.becomeFirstResponder()
  }

  override func resignFirstResponder() -> Bool {
    defer {
      redraw(selections: selectedRanges)
      interaction?.selectionDidChange()
    }
    return super.resignFirstResponder()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didBecomeKeyNotification, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didResignKeyNotification, object: nil)
    guard let window else { return }
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowKeyStateDidChange(_:)), name: name, object: window)
    }
  }

  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = newSize.width != frame.width
    super.setFrameSize(newSize)
    // The fragments in view lay out again, so that their rendering surfaces take the new width;
    // the others ask for it when they come into view. Laying out the whole text again would make
    // TextKit lay out every paragraph above the visible part, as often as a line typed at the
    // right edge makes the text wider.
    if widthChanged, let textLayoutManager,
      let viewport = textLayoutManager.textViewportLayoutController.viewportRange
    {
      textLayoutManager.invalidateLayout(for: viewport)
    }
  }

  /// The attributes of all text: one font, lines of the grid's height, broken at words.
  ///
  /// Each paragraph indents its lines after the first beyond its own indentation, which the
  /// content storage asks the view for as it makes the paragraph.
  ///
  /// Whether lines wrap at all depends on the width of the text container alone, so that turning
  /// wrapping on or off leaves the attributes, and with them the colors of the text, as they are.
  var textAttributes: [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = theme.rowHeight
    paragraph.maximumLineHeight = theme.rowHeight
    paragraph.lineBreakMode = .byWordWrapping
    // TextKit would otherwise move words to the next line to avoid a short last line, which the
    // count of screen lines could not foresee.
    paragraph.lineBreakStrategy = []
    paragraph.tabStops = []
    paragraph.defaultTabInterval = CGFloat(theme.tabWidth) * theme.characterWidth
    return [
      .font: theme.font,
      .foregroundColor: Theme.textColor,
      .paragraphStyle: paragraph,
    ]
  }

  private func reloadHighlights() {
    highlightsByBlock.removeAll()
    guard let textLayoutManager else { return }
    textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
  }

  /// Whether the selection shows in the accent color, as the focused selection of the key window,
  /// or in the quieter color of a selection without focus.
  var isSelectionEmphasized: Bool {
    guard let window else { return false }
    return window.isKeyWindow && window.firstResponder === self
  }

  /// The fill of the selection as the fragments draw it now.
  var selectionFill: NSColor {
    theme.selectionFill(isEmphasized: isSelectionEmphasized)
  }

  @objc private func selectionDidChange(_ notification: Notification) {
    showWholeTheLongLinesOfTheSelection()
    redraw(selections: drawnSelection + selectedRanges)
    drawnSelection = selectedRanges
    interaction?.selectionDidChange()
  }

  @objc private func windowKeyStateDidChange(_ notification: Notification) {
    redraw(selections: selectedRanges)
    interaction?.selectionDidChange()
  }

  /// Draws the rows that `selections` touch again.
  private func redraw(selections: [NSValue]) {
    for selection in selections.map(\.rangeValue) where selection.length > 0 {
      let first = grid.row(containingOffset: selection.location)
      let last = grid.row(containingOffset: selection.location + selection.length)
      redraw(rows: first..<last + 1)
    }
  }

  func redraw(rows: Range<Int>) {
    guard let textLayoutManager else { return }
    let offsets = grid.paragraphOffsets(ofRows: rows)
    let documentStart = textLayoutManager.documentRange.location
    guard
      let start = textLayoutManager.location(documentStart, offsetBy: offsets.lowerBound),
      let end = textLayoutManager.location(documentStart, offsetBy: offsets.upperBound),
      let range = NSTextRange(location: start, end: end)
    else { return }
    // Draws the fragments of the rows again, which ask for their painting as they draw.
    textLayoutManager.invalidateRenderingAttributes(for: range)
    applyTextColors(in: offsets)
    let lines = displayRows.lines(ofRows: rows)
    setNeedsDisplayOfFragments(
      in: CGRect(
        x: bounds.minX, y: CGFloat(lines.lowerBound) * theme.rowHeight, width: bounds.width,
        height: CGFloat(lines.count) * theme.rowHeight))
  }

  /// Marks the views within the text view that show the fragments in `rect` as needing display.
  ///
  /// TextKit draws each fragment into a view of its own and keeps what it drew until the
  /// fragment's layout changes. Invalidating the rendering attributes of a range lays nothing
  /// out, so in a window on screen the fragments would keep their old look.
  func setNeedsDisplayOfFragments(in rect: CGRect) {
    func mark(_ view: NSView) {
      for subview in view.subviews {
        let area = subview.convert(rect, from: self).intersection(subview.bounds)
        guard !area.isEmpty else { continue }
        subview.setNeedsDisplay(area)
        mark(subview)
      }
    }
    mark(self)
  }

  /// How `row` is shaded across the pane, the one place that the text and the gutter both ask.
  ///
  /// The row is filled in the tint of its block, preview or own tint, or stays on the text
  /// background; the screen lines below its text, where the row wraps less than in a pane it
  /// lines up with, are as quiet as a filler row.
  func shading(atRow row: Int) -> RowShading {
    let blockIndex = content.blockIndex(atRow: row)
    let isCurrent = blockIndex != nil && blockIndex == currentBlock
    let style = style(ofRow: row)
    return RowShading(
      fill: theme.rowFill(for: style, isFiller: content.isFiller(row: row), isCurrent: isCurrent),
      paddingFill: theme.rowFill(for: style, isFiller: true, isCurrent: isCurrent),
      edges: edges(atRow: row), style: style)
  }

  /// The number of screen lines that the text of `row` takes at the width of the pane.
  func textLines(ofRow row: Int) -> Int {
    ownWrappedRows.lines(ofRow: row)
  }

  /// The hairlines at the edges of changed blocks in `row`: at the top of the first row of a
  /// block, and at the bottom of its last row unless another block follows at once, whose top
  /// edge is the line between them.
  ///
  /// The hairlines keep two blocks of the same color apart where they touch, also on panes that
  /// show no marker there, and let a block read as a band across the panes. Between two tinted
  /// blocks of the same style, or where the lower one has no marker, the hairline alone shows
  /// the boundary and takes the stronger color.
  ///
  /// Rows with a tint of their own have edges where the tint changes, within a block or outside
  /// every block; between rows typed by hand and tinted rows, the hairline is the only boundary,
  /// as there is no marker.
  private func edges(atRow row: Int) -> RowShading.Edges {
    var edges = blockEdges(atRow: row)
    // The hairline of a block without rows is the only sign of it in the text, so it takes the
    // place of any other edge there.
    if let block = content.markedBlockIndex(atBoundary: row) {
      edges.top = hairlineColor(ofBlock: block)
    }
    if row == grid.rowCount - 1, let block = content.markedBlockIndex(atBoundary: row + 1) {
      edges.bottom = hairlineColor(ofBlock: block)
    }
    return edges
  }

  /// The color of the hairline of the block without rows at `block`: the color of its edges, or
  /// the stronger color of signs while it is current.
  private func hairlineColor(ofBlock block: Int) -> NSColor? {
    theme.edgeColor(
      between: nil, and: content.blocks[block].style, isOnlyBoundary: block == currentBlock)
  }

  /// The hairlines at the edges of the changed block that `row` belongs to and between its
  /// parts, if any.
  private func blockEdges(atRow row: Int) -> RowShading.Edges {
    guard let block = content.blockIndex(atRow: row) else { return tintEdges(atRow: row) }
    let rows = content.blocks[block].rows
    var edges = tintEdges(atRow: row)
    let tints = content.rowTints
    if row == rows.lowerBound {
      let touchesBlockAbove =
        row > 0 && (content.blockIndex(atRow: row - 1) != nil || tints[row - 1] != nil)
      let upper = touchesBlockAbove ? style(ofRow: row - 1) : nil
      let lower = style(ofRow: row)
      let bothTinted = upper.map { $0 != .unchanged } == true && lower != .unchanged
      let isOnlyBoundary = bothTinted && (upper == lower || content.blocks[block].marker == nil)
      edges.top = theme.edgeColor(between: upper, and: lower, isOnlyBoundary: isOnlyBoundary)
    }
    if let part = content.blocks[block].lowerPart, row == part.firstRow {
      // The parts of a block meet like two blocks that touch.
      edges.top = theme.edgeColor(
        between: content.blocks[block].style, and: part.style,
        isOnlyBoundary: part.style == content.blocks[block].style || part.marker == nil)
    }
    if row == rows.upperBound - 1 {
      // A row with a tint of its own below draws the edge at its top.
      let touchesBlockBelow =
        row + 1 < content.lineNumbers.count
        && (content.blockIndex(atRow: row + 1) != nil
          || tints[row + 1] != nil && style(ofRow: row + 1) != style(ofRow: row))
      if !touchesBlockBelow {
        edges.bottom = theme.edgeColor(
          between: style(ofRow: row), and: nil, isOnlyBoundary: false)
      }
    }
    return edges
  }

  /// The hairlines in `row` where rows with a tint of their own meet other rows.
  ///
  /// A row whose tint differs from the row above has one at its top, if either has a tint of its
  /// own and the row itself is tinted; a row with a tint of its own above a row outside every
  /// block has one at its bottom. Between rows typed by hand and tinted rows, the hairline is the
  /// only boundary. The edges of blocks, drawn after these, take precedence.
  private func tintEdges(atRow row: Int) -> RowShading.Edges {
    let tints = content.rowTints
    var edges = RowShading.Edges()
    guard !tints.isEmpty else { return edges }
    let hasTint = tints[row] != nil
    if row > 0, hasTint || tints[row - 1] != nil {
      let upper = style(ofRow: row - 1)
      let lower = style(ofRow: row)
      if upper != lower && lower != .unchanged {
        let bothTinted = upper != .unchanged
        edges.top = theme.edgeColor(
          between: bothTinted ? upper : nil, and: lower,
          isOnlyBoundary: bothTinted && (upper == .handwritten || lower == .handwritten))
      }
    }
    let isLastBeforeBackground =
      row + 1 == grid.rowCount || content.blockIndex(atRow: row + 1) == nil && tints[row + 1] == nil
    if hasTint, isLastBeforeBackground {
      edges.bottom = theme.edgeColor(between: style(ofRow: row), and: nil, isOnlyBoundary: false)
    }
    return edges
  }

  /// The changed runs within `rows` with their fills, and the places of removed text with the
  /// colors of their marks.
  func changes(inRows rows: Range<Int>) -> (
    runs: [RowLayoutFragment.Run], removals: [RowLayoutFragment.Removal]
  ) {
    var runs: [RowLayoutFragment.Run] = []
    var removals: [RowLayoutFragment.Removal] = []
    for row in rows {
      guard let blockIndex = content.blockIndex(atRow: row) else { continue }
      let style = content.blocks[blockIndex].style(atRow: row)
      // A line that is too long to show whole shows no change beyond its cut.
      let rowOffsets = shownOffsets(ofParagraph: grid.paragraphOffsets(ofRows: row..<row + 1))
      let fill = theme.runFill(for: style, isCurrent: blockIndex == currentBlock)
      let highlights = highlights(forBlock: blockIndex)
      // The runs are sorted, so those of the row follow each other.
      var index = highlights.partitioningIndex(where: { $0.upperBound >= rowOffsets.lowerBound })
      while index < highlights.count && highlights[index].lowerBound <= rowOffsets.upperBound {
        let range = highlights[index]
        index += 1
        if range.isEmpty {
          // Each removal belongs to exactly one row, even where rows meet.
          if grid.row(containingOffset: range.lowerBound) == row {
            removals.append(
              RowLayoutFragment.Removal(
                offset: range.lowerBound, color: theme.markerColor(for: style)))
          }
        } else if let fill, range.overlaps(rowOffsets) {
          runs.append(RowLayoutFragment.Run(range: range.clamped(to: rowOffsets), fill: fill))
        }
      }
    }
    let places = content.ignoredDifferencePlaces
    if !places.isEmpty {
      let offsets = shownOffsets(ofParagraph: grid.paragraphOffsets(ofRows: rows))
      var index = places.partitioningIndex { $0.upperBound > offsets.lowerBound }
      while index < places.count, places[index].lowerBound < offsets.upperBound {
        runs.append(
          RowLayoutFragment.Run(
            range: places[index].clamped(to: offsets), fill: theme.ignoredDifferenceFill))
        index += 1
      }
    }
    return (runs, removals)
  }

  /// The places of removed text in `rows`, for the gutter's accessibility elements.
  func removalRows(in rows: Range<Int>) -> [Int] {
    changes(inRows: rows).removals.map { grid.row(containingOffset: $0.offset) }
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    if let highlights = highlightsByBlock[block] {
      return highlights
    }
    let highlights = highlightProvider?.highlights(forBlock: block) ?? []
    highlightsByBlock[block] = highlights
    return highlights
  }

  /// Stops a debug build when something switches the view to TextKit 1, which happens for good
  /// as soon as anything asks for its `layoutManager`.
  @objc private func willSwitchToLayoutManager(_ notification: Notification) {
    assertionFailure("A pane's text view must stay on TextKit 2")
  }
}

extension PaneTextView: @MainActor NSTextLayoutManagerDelegate {
  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    RowLayoutFragment(
      textElement: textElement, range: textElement.elementRange, rowHeight: theme.rowHeight,
      textVersion: textVersion, painter: self)
  }
}

extension PaneTextView: @MainActor NSTextContentStorageDelegate {
  /// Indents the lines after the first of the paragraph in `range` beyond its own indentation,
  /// so that a wrapped row goes on below its own text, and cuts a line that is too long to show
  /// whole; the text itself stays as it is.
  ///
  /// The indent takes effect only where a row wraps, so paragraphs need not be made again when
  /// wrapping is turned on or off.
  func textContentStorage(
    _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
  ) -> NSTextParagraph? {
    guard let textStorage = textContentStorage.textStorage, range.length > 0 else { return nil }
    let paragraph = NSMutableAttributedString(
      attributedString: textStorage.attributedSubstring(from: range))
    if let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
      as? NSParagraphStyle, let indented = style.mutableCopy() as? NSMutableParagraphStyle
    {
      indented.headIndent = RowWrapping.continuationIndent(
        of: paragraph.string as NSString, theme: theme)
      paragraph.addAttribute(
        .paragraphStyle, value: indented, range: NSRange(location: 0, length: paragraph.length))
    }
    if !wholeRows.rows.contains(grid.row(containingOffset: range.location)) {
      cutLongLine(paragraph)
    }
    return NSTextParagraph(attributedString: paragraph)
  }

  /// Leaves out the paragraphs of the rows that collapsed runs hide, so that they take no room;
  /// the first row of each run stays, as the place of its bar.
  func textContentManager(
    _ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
    options: NSTextContentManager.EnumerationOptions
  ) -> Bool {
    guard !displayRows.runs.isEmpty, let range = textElement.elementRange else { return true }
    let start = textContentManager.offset(
      from: textContentManager.documentRange.location, to: range.location)
    return !displayRows.isHidden(row: grid.row(containingOffset: start))
  }
}

extension PaneTextView: RowPainter {
  func lines(ofRows rows: Range<Int>) -> Range<Int> {
    displayRows.lines(ofRows: rows)
  }

  func rows(ofParagraphFrom start: Int, to end: Int) -> Range<Int> {
    grid.rows(ofParagraphFrom: start, to: end)
  }

  var extent: RowLayoutFragment.Extent {
    RowLayoutFragment.Extent(
      containerInset: textContainerOrigin.x, width: bounds.width, textLift: theme.textLift,
      removalMarkWidth: Theme.removalMarkWidth, removalMarkSeam: Theme.markSeam,
      hairline: RowShading.hairline(in: window))
  }

  func painting(forRows rows: Range<Int>) -> RowLayoutFragment.Painting {
    let changes = changes(inRows: rows)
    let paragraph = grid.paragraphOffsets(ofRows: rows)
    let selectionFill = selectionFill
    let selections = selectedRanges.map(\.rangeValue).compactMap { selection in
      let range = selection.location..<selection.location + selection.length
      return range.isEmpty || !range.overlaps(paragraph)
        ? nil : RowLayoutFragment.Run(range: range, fill: selectionFill)
    }
    return RowLayoutFragment.Painting(
      extent: extent, isCollapsed: displayRows.runIndex(containingRow: rows.lowerBound) != nil,
      rowLines: rows.map { displayRows.lines(ofRows: $0..<$0 + 1).count },
      shadings: rows.map(shading(atRow:)),
      background: Theme.backgroundColor,
      textBandHeight: theme.textBandHeight, runs: changes.runs,
      matches: searchMatchRuns(in: paragraph),
      selections: selections,
      removals: changes.removals,
      invisibles: invisibles(inRows: rows))
  }

  /// The invisible characters that `rows` show: all of them while the pane shows them, and the
  /// spaces and tabs of the places of ignored differences, which tell what differs there, in a
  /// stronger color.
  private func invisibles(inRows rows: Range<Int>) -> RowLayoutFragment.Invisibles? {
    guard showsInvisibles || !content.ignoredDifferencePlaces.isEmpty else { return nil }
    return RowLayoutFragment.Invisibles(
      lineEndings: showsInvisibles ? Array(content.lineEndings[rows]) : nil,
      places: content.ignoredDifferencePlaces, color: theme.invisibleCharacterColor,
      placeColor: theme.ignoredDifferenceSymbolColor, baseline: theme.baseline)
  }
}
