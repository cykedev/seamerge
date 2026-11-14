import AppKit

/// A pane: the text of one side on the row grid, with line numbers and markers in its gutter.
///
/// The pane shows what it is given and knows neither the engine nor the merge model. Row *r* of
/// the content lies at `r × theme.rowHeight` from the top of the text, in every pane alike, less
/// the rows that collapsed runs above it hide, each run taking the one row of its bar, and plus
/// the screen lines that wrapped rows above it take beyond their first.
///
/// The pane moves its text only when the user scrolls, when it is told to reveal a block, and
/// when the selection or a find result has to come into view; nothing else shifts what it shows.
public final class PaneView: NSView {
  /// The fonts, metrics and colors of the pane.
  public var theme: Theme {
    didSet { show(content, collapsedRuns: collapsedRuns) }
  }

  /// What the pane shows.
  ///
  /// Setting the content alone shows it without collapsed runs, since the old runs need not fit
  /// its rows; to show it with runs, use ``setContent(_:collapsedRuns:)``.
  ///
  /// - Precondition: The content has one line number and one line ending per row.
  public var content: PaneContent {
    get { textView.content }
    set { setContent(newValue, collapsedRuns: []) }
  }

  /// Shows `content` with `collapsedRuns`, both at once.
  ///
  /// The pane keeps its scroll position, as it does for new content alone.
  ///
  /// - Precondition: The content has one line number and one line ending per row, and the runs
  ///   are sorted, do not overlap and lie within its rows.
  public func setContent(_ content: PaneContent, collapsedRuns: [CollapsedRun]) {
    show(content, collapsedRuns: collapsedRuns)
  }

  /// Gives the content new blocks, previews and row tints and keeps its text, rows and
  /// line numbers: what the owner of an editable pane gives it after an edit, in place of new
  /// content.
  ///
  /// Only the rows whose block, preview or tint changed are drawn again, so that typing stays
  /// fast in a long text. A preview that turns into text, or text into a preview, cross-fades.
  ///
  /// - Precondition: The blocks are sorted, do not overlap and lie within the rows; the previews
  ///   are sorted, do not overlap and lie within the text; the rows of the tints lie within the
  ///   rows.
  public func setBlocks(
    _ blocks: [PaneBlock], previews: [PanePreview], rowTints: [Int: BlockStyle]
  ) {
    textView.setBlocks(blocks, previews: previews, rowTints: rowTints)
    gutterView.content = content
    gutterView.currentBlock = textView.currentBlock
    decisionColumn?.update()
  }

  /// The runs of rows that the pane hides, each behind a bar one row high that the user can
  /// expand.
  ///
  /// The pane keeps the rows in view where they are while its runs change. The delegate learns
  /// when the user asks to expand a run; the pane leaves it collapsed until it is told otherwise.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows of the content.
  public var collapsedRuns: [CollapsedRun] {
    get { displayRows.runs }
    set { collapse(newValue) }
  }

  /// The runs that the user expanded and that may collapse again, in rows of the content.
  ///
  /// While the pointer is over the rows of one of them, a sign beside its first row in the
  /// gutter collapses it; the delegate learns when the user presses it.
  ///
  /// - Precondition: The runs are sorted, do not overlap, lie within the rows of the content and
  ///   outside its collapsed runs.
  public var expandedRuns: [CollapsedRun] {
    get { gutterView.expandedRuns }
    set { gutterView.expandedRuns = newValue }
  }

  /// The index of the current block in the content's blocks, or `nil` if there is none.
  ///
  /// The rows of the current block are tinted more strongly and its line-number cells filled.
  public var currentBlock: Int? {
    get { textView.currentBlock }
    set {
      textView.setCurrentBlock(newValue)
      gutterView.currentBlock = textView.currentBlock
      decisionColumn?.update()
    }
  }

  /// Supplies the changed runs within the lines of the blocks; the pane does not retain it.
  public var highlightProvider: (any PaneHighlightProvider)? {
    get { textView.highlightProvider }
    set { textView.highlightProvider = newValue }
  }

  /// Supplies the tokens of the lines that are colored by their syntax.
  ///
  /// The pane does not retain it. Without one, the code keeps the color of text; setting a
  /// provider colors every row anew.
  public var syntaxProvider: (any PaneSyntaxProvider)? {
    get { textView.syntaxProvider }
    set { textView.syntaxProvider = newValue }
  }

  /// Colors the code of `rows` anew, after the syntax provider changed the tokens of their lines.
  ///
  /// - Parameter rows: Rows of the content; those beyond its rows are left out.
  public func syntaxDidChange(inRows rows: Range<Int>) {
    textView.syntaxDidChange(inRows: rows)
  }

  /// Whether the keyboard focus lies in the pane: in its text, or beside it, such as in the
  /// decision column of the result or on the bar of a collapsed run.
  public var holdsFocus: Bool {
    (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
  }

  /// A number that changes whenever the pane gets other content.
  private(set) var contentGeneration = 0

  /// Learns about clicks and supplies the context menu; the pane does not retain it.
  public weak var delegate: (any PaneViewDelegate)?

  /// Decides every edit of the text; the pane does not retain it.
  ///
  /// With a delegate, the user can edit the text, and every edit passes through the delegate
  /// before it changes the text; without one, the text is read-only. The text view keeps no undo
  /// of its own: undo belongs to the delegate, which knows what an edit means.
  public weak var editingDelegate: (any PaneEditingDelegate)? {
    didSet { textView.isEditable = editingDelegate != nil }
  }

  /// Carries out `edits` in order, each in the text that the edits before it left, without
  /// asking the editing delegate, and returns the text that each of them replaced.
  ///
  /// Use it for what the delegate decides on its own, such as choosing a source or undoing an
  /// edit. The insertion point and the selection move with the text as with any edit. Edits that
  /// turn a preview into text, or text into a preview, cross-fade.
  ///
  /// - Precondition: Each range lies within the text as the edits before it left it.
  @discardableResult
  public func carryOut(_ edits: [PaneEdit]) -> [String] {
    textView.carryOut(edits)
  }

  /// Whether spaces, tabs and line endings show as quiet symbols.
  ///
  /// The symbols are drawn only: they are neither copied nor read by VoiceOver.
  public var showsInvisibles: Bool {
    get { textView.showsInvisibles }
    set { textView.showsInvisibles = newValue }
  }

  /// Whether long lines wrap at the width of the pane rather than run on beyond its right edge.
  ///
  /// A row that wraps takes as many screen lines as it needs, the lines after its first
  /// indented and without a line number. The panes that a ``RowAlignment`` lines up with this
  /// one show the row as high, with a quiet fill below a version that needs fewer lines.
  public var wrapsLines = false {
    didSet {
      guard wrapsLines != oldValue else { return }
      updateLineWrapping()
      needsLayout = true
    }
  }

  /// The alignment that the pane's rows line up in with other panes, if any.
  weak var rowAlignment: RowAlignment?

  /// The overview bar that serves as the pane's vertical scroller, beside its right edge, or
  /// `nil` for a pane without one, which scrolls along with a pane that has it.
  ///
  /// The bar sits beside the scroll view rather than in it, so that the scroll view shows its
  /// horizontal scroller in the style that the user chose, as in every other pane.
  public var overviewBar: OverviewBar? {
    didSet {
      guard overviewBar !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let overviewBar {
        overviewBar.target = self
        overviewBar.action = #selector(overviewBarDidScroll(_:))
        overviewBar.displayRows = displayRows
        addSubview(overviewBar)
      }
      needsLayout = true
    }
  }

  /// The decision column beside the right edge of the text, between the text and the overview
  /// bar, or `nil` for a pane without one.
  ///
  /// The pane places the column and keeps it in step with its rows, its scroll position and its
  /// current block.
  public var decisionColumn: DecisionColumnView? {
    didSet {
      guard decisionColumn !== oldValue else { return }
      oldValue?.removeFromSuperview()
      oldValue?.host = nil
      if let decisionColumn {
        decisionColumn.host = self
        addSubview(decisionColumn, positioned: .below, relativeTo: runBarLayer)
      }
      needsLayout = true
    }
  }

  /// The view that shows the text, for selection and the find bar.
  public var documentView: NSTextView { textView }

  /// The narrowest the pane gets: room for the gutter, a short line of code and the overview
  /// bar, so that its neighbors and the dividers between them stay usable.
  public var minimumWidth: CGFloat {
    let text = CGFloat(Theme.minimumTextColumns) * theme.characterWidth + 2 * Theme.textInset
    let bar = overviewBar == nil ? 0 : Theme.overviewBarWidth
    let column = decisionColumn?.width ?? 0
    let width = gutterView.fittingWidth + text + column + bar
    return (width / Theme.layoutGrid).rounded(.up) * Theme.layoutGrid
  }

  /// Scrolls the pane, and the panes coupled with it, so that the first change of `block` comes
  /// into view with some text before it, unless it is in view already.
  public func reveal(block: Int) {
    guard content.blocks.indices.contains(block) else { return }
    textView.reveal(offset: textView.firstChangeOffset(ofBlock: block))
  }

  /// The row and block at `point`, in the pane's coordinates.
  ///
  /// On the bar of a collapsed run, the row is the first one that the run hides.
  public func hit(at point: CGPoint) -> PaneHit {
    let y = point.y + clipView.bounds.minY
    let line = Int((y / theme.rowHeight).rounded(.down))
    return hit(atRow: displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: line)))
  }

  /// The vertical extent of `rows` in the text, from the top of their first screen line to the
  /// bottom of their last; for an empty range, the boundary that it lies on.
  ///
  /// Rows behind the bar of a collapsed run take the place of the bar.
  public func verticalSpan(ofRows rows: Range<Int>) -> Range<CGFloat> {
    let lines = displayRows.lines(ofRows: rows)
    return CGFloat(lines.lowerBound) * rowHeight..<CGFloat(lines.upperBound) * rowHeight
  }

  /// The rows as the pane shows them, with its collapsed runs.
  var displayRows: DisplayRows { textView.displayRows }

  /// The bar of each collapsed run that is in view, by the index of its run.
  var runBars: [Int: CollapsedRunBar] = [:]

  /// The coupling that the pane scrolls in, if any.
  weak var scrollSync: ScrollSync?

  /// The scroll range sideways that the pane shares with the panes it is coupled with, or `nil`
  /// while it is coupled with none.
  var sharedHorizontalScrollRange: CGFloat? {
    didSet {
      if sharedHorizontalScrollRange != oldValue {
        needsLayout = true
      }
    }
  }

  /// How far the pane's own text reaches beyond the visible width.
  private(set) var ownHorizontalScrollRange: CGFloat = 0

  /// The view that clips the text to the visible part, whose bounds origin is the scroll
  /// position.
  var clipView: NSClipView { scrollView.contentView }

  /// The top left corner of the visible part of the text.
  var scrollOrigin: CGPoint { clipView.bounds.origin }

  /// The height of the visible part of the text.
  var visibleHeight: CGFloat { clipView.bounds.height }

  /// The height of a row.
  var rowHeight: CGFloat { theme.rowHeight }

  /// How far the text scrolls vertically.
  var verticalScrollRange: CGFloat {
    max(textView.frame.height - clipView.bounds.height, 0)
  }

  /// Moves the top left corner of the visible part of the text to `origin`, as given.
  func scroll(to origin: CGPoint) {
    clipView.scroll(to: origin)
    scrollView.reflectScrolledClipView(clipView)
  }

  let textView = PaneTextView()
  let gutterView = GutterView()
  let runBarLayer = CollapsedRunBarLayer()
  private let scrollView = PaneScrollView()

  /// Creates an empty pane.
  public init(theme: Theme = Theme()) {
    self.theme = theme
    super.init(frame: .zero)
    textView.configure(theme: theme)
    scrollView.documentView = textView
    // The cross-fade between a preview and text runs on the layer of the clip view, which a
    // window without a screen does not give it on its own.
    scrollView.contentView.wantsLayer = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(clipViewBoundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView)
    NotificationCenter.default.addObserver(
      self, selector: #selector(liveScrollDidStart(_:)),
      name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
    NotificationCenter.default.addObserver(
      self, selector: #selector(liveScrollDidEnd(_:)),
      name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
    gutterView.removalRows = { [weak textView] rows in textView?.removalRows(in: rows) ?? [] }
    gutterView.hasFocus = { [weak self] in
      self.map { $0.window?.isKeyWindow == true && $0.holdsFocus } ?? false
    }
    textView.interaction = self
    gutterView.interaction = self
    addSubview(gutterView)
    addSubview(scrollView)
    addSubview(runBarLayer)
    show(.empty, collapsedRuns: [])
  }

  /// Panes are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  isolated deinit {
    scrollSync?.remove(self)
  }

  public override var isFlipped: Bool { true }

  public override func layout() {
    super.layout()
    let gutterWidth = gutterView.fittingWidth
    let barWidth = overviewBar == nil ? 0 : Theme.overviewBarWidth
    let columnWidth = decisionColumn?.width ?? 0
    gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    scrollView.frame = CGRect(
      x: gutterWidth, y: 0, width: max(bounds.width - gutterWidth - columnWidth - barWidth, 0),
      height: bounds.height)
    decisionColumn?.frame = CGRect(
      x: bounds.width - barWidth - columnWidth, y: 0, width: columnWidth, height: bounds.height)
    overviewBar?.frame = CGRect(
      x: bounds.width - barWidth, y: 0, width: barWidth, height: bounds.height)
    scrollView.tile()
    updateLineWrapping()
    let visibleWidth = clipView.bounds.width
    let ownRange = wrapsLines ? 0 : max(textView.textWidth - visibleWidth, 0)
    if ownRange != ownHorizontalScrollRange {
      ownHorizontalScrollRange = ownRange
      scrollSync?.updateHorizontalScrollRange()
    }
    let range = sharedHorizontalScrollRange ?? ownRange
    let hasHorizontalScroller = range > 0
    if scrollView.hasHorizontalScroller != hasHorizontalScroller {
      scrollView.hasHorizontalScroller = hasHorizontalScroller
      scrollView.tile()
    }
    // At least as high as the view, so that a click below the last line reaches the text and
    // puts the insertion point at its end, as in any editor.
    textView.setFrameSize(
      CGSize(
        width: visibleWidth + range,
        height: max(CGFloat(displayRows.lineCount) * rowHeight, clipView.bounds.height)))
    textDidScroll()
  }

  /// Hands scrolling over the gutter and the overview bar to the text.
  public override func scrollWheel(with event: NSEvent) {
    scrollView.scrollWheel(with: event)
  }

  private func show(_ content: PaneContent, collapsedRuns: [CollapsedRun]) {
    contentGeneration += 1
    // The runs, and with them the indices of the bars, may change; the text reports its new
    // selection while it changes.
    removeRunBars()
    // The old expanded runs need not fit the new rows; the owner hands new ones.
    gutterView.expandedRuns = []
    textView.show(content, collapsedRuns: collapsedRuns, theme: theme)
    alignRows()
    gutterView.theme = theme
    gutterView.content = content
    gutterView.currentBlock = textView.currentBlock
    showDisplayRows()
    decisionColumn?.update()
    needsLayout = true
  }

  /// Wraps the lines at the width that the text has now, if they wrap, and lines the rows up
  /// again where that changed the rows that wrap.
  ///
  /// A pane narrower than its minimum, such as one whose split view item is collapsed, does not
  /// wrap, so that it does not make the rows of its neighbors taller. While the user drags the
  /// edge of the window far down a long text, the lines keep their width until the drag ends.
  func updateLineWrapping() {
    if inLiveResize && textView.lineWrapping != nil && rowsAboveView > Self.rowsAboveViewToWrapLive
    {
      return
    }
    let width = clipView.bounds.width - 2 * Theme.textInset
    let fits = width >= CGFloat(Theme.minimumTextColumns) * theme.characterWidth
    if textView.wrapLines(atWidth: wrapsLines && fits ? width : nil) {
      alignRows()
    }
  }

  /// The most rows above the visible text at which lines wrap anew at every step while the user
  /// drags the edge of the window; beyond, they wrap anew once the drag ends.
  ///
  /// TextKit lays out every paragraph above the visible text again when the width of the lines
  /// changes, some 12 µs each, so that a step far down a long file would take most of a second.
  private static let rowsAboveViewToWrapLive = 2_000

  /// The number of rows above the visible text.
  private var rowsAboveView: Int {
    let line = Int((clipView.bounds.minY / rowHeight).rounded(.down))
    return displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: line))
  }

  public override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()
    updateLineWrapping()
    needsLayout = true
  }

  /// Gives the pane the rows that wrap in it or in the panes it lines up with.
  func alignRows() {
    if let rowAlignment {
      rowAlignment.align()
    } else {
      showWrappedRows(textView.ownWrappedRows)
    }
  }

  /// Shows each row as high as `wrappedRows` says.
  func showWrappedRows(_ wrappedRows: WrappedRows) {
    guard textView.setWrappedRows(wrappedRows) else { return }
    removeRunBars()
    showDisplayRows()
    decisionColumn?.update()
    needsLayout = true
  }

  /// Hands the rows as the pane shows them to the gutter and the overview bar.
  func showDisplayRows() {
    gutterView.displayRows = displayRows
    overviewBar?.displayRows = displayRows
  }

  @objc private func clipViewBoundsDidChange(_ notification: Notification) {
    textDidScroll()
    textView.visibleTextDidMove()
  }

  @objc private func liveScrollDidStart(_ notification: Notification) {
    textView.liveScrollDidStart()
  }

  @objc private func liveScrollDidEnd(_ notification: Notification) {
    textView.liveScrollDidEnd()
  }

  /// Moves the gutter, the bars of collapsed runs and the overview bar along with the text.
  private func textDidScroll() {
    let visible = clipView.bounds
    gutterView.scrollOffset = visible.minY
    placeRunBars()
    decisionColumn?.update()
    guard let overviewBar else { return }
    let height = textView.frame.height
    overviewBar.isEnabled = height > visible.height
    overviewBar.knobProportion = height > 0 ? min(visible.height / height, 1) : 1
    overviewBar.doubleValue = verticalScrollRange > 0 ? visible.minY / verticalScrollRange : 0
  }

  /// Scrolls the text to the place of the overview bar's knob, or by a page.
  @objc private func overviewBarDidScroll(_ sender: OverviewBar) {
    let visible = clipView.bounds
    let y: CGFloat =
      switch sender.hitPart {
      case .decrementPage where !sender.isPlacingKnob: visible.minY - visible.height
      case .incrementPage where !sender.isPlacingKnob: visible.minY + visible.height
      default: sender.doubleValue * verticalScrollRange
      }
    scroll(to: CGPoint(x: visible.minX, y: min(max(y, 0), verticalScrollRange).rounded()))
  }
}

extension PaneView: RowInteraction {
  var suppliesMenus: Bool { delegate != nil }

  /// Gives the pane the keyboard focus, as a click beside its text does: to the text of a pane
  /// without a decision column; to the decision column of the result, which leaves single keys
  /// to the commands that decide blocks, unless its text has the focus already and keeps it.
  func takeFocus() {
    guard let window else { return }
    guard let decisionColumn else {
      window.makeFirstResponder(textView)
      return
    }
    if window.firstResponder !== textView {
      window.makeFirstResponder(decisionColumn)
    }
  }

  func rowWasClicked(_ row: Int) {
    delegate?.pane(self, didClick: hit(atRow: row))
  }

  func menu(forRow row: Int) -> NSMenu? {
    delegate?.pane(self, menuFor: hit(atRow: row))
  }

  func selectionDidChange() {
    markSelectedRunBars()
    // The cells of the current block show whether the pane has the focus.
    gutterView.needsDisplay = true
  }

  func askToExpandRun(at index: Int) {
    delegate?.pane(self, didAskToExpand: displayRows.runs[index])
  }

  func askToCollapse(_ run: CollapsedRun) {
    delegate?.pane(self, didAskToCollapse: run)
  }

  func edits(for edit: PaneEdit) -> [PaneEdit] {
    editingDelegate?.pane(self, editsFor: edit) ?? []
  }

  func didCarryOut(_ edits: [PaneEdit], replacing replacedTexts: [String]) {
    editingDelegate?.pane(self, didCarryOut: edits, replacing: replacedTexts)
  }

  func textDidChangeWithoutAnnouncing(_ edit: PaneEdit) {
    editingDelegate?.pane(self, didChangeTextWithoutAnnouncing: edit)
  }

  func textDidChange() {
    rowAlignment?.align()
    removeRunBars()
    gutterView.content = content
    showDisplayRows()
    decisionColumn?.update()
    needsLayout = true
  }

  private func hit(atRow row: Int) -> PaneHit {
    PaneHit(row: row, block: content.blockIndex(atRow: row))
  }
}

extension PaneView: DecisionColumnHost {
  func top(ofBlock block: Int) -> CGFloat? {
    guard content.blocks.indices.contains(block) else { return nil }
    let row = content.blocks[block].rows.lowerBound
    guard row >= displayRows.rowCount || !displayRows.isHidden(row: row) else { return nil }
    return verticalSpan(ofRows: row..<row).lowerBound - clipView.bounds.minY
  }

  func rowCenter(ofBlock block: Int) -> CGFloat? {
    guard content.blocks.indices.contains(block) else { return nil }
    let rows = content.blocks[block].rows
    let scrollOffset = clipView.bounds.minY
    guard !rows.isEmpty else {
      // A block without rows lies on the boundary before the row it would start at.
      let row = rows.lowerBound
      if row < displayRows.rowCount && displayRows.isHidden(row: row) { return nil }
      return verticalSpan(ofRows: rows).lowerBound - scrollOffset
    }
    guard displayRows.runIndex(containingRow: rows.lowerBound) == nil else { return nil }
    // The middle of the first screen line, beside the start of the block's text.
    return verticalSpan(ofRows: rows).lowerBound + rowHeight / 2 - scrollOffset
  }

  var rowsExtent: ClosedRange<CGFloat> {
    let top = -clipView.bounds.minY
    return top...top + CGFloat(displayRows.lineCount) * rowHeight
  }

  func liesBetweenRows(_ block: Int) -> Bool {
    content.blocks.indices.contains(block) && content.blocks[block].rows.isEmpty
  }

  func block(atY y: CGFloat) -> Int? {
    let line = Int(((y + clipView.bounds.minY) / rowHeight).rounded(.down))
    let displayRow = line >= 0 ? displayRows.displayRow(atLine: line) : -1
    guard displayRow >= 0, displayRow < displayRows.count,
      displayRows.runIndex(atDisplayRow: displayRow) == nil
    else { return nil }
    return content.blockIndex(atRow: displayRows.row(atDisplayRow: displayRow))
  }

  func focusDidChange() {
    gutterView.needsDisplay = true
  }

  func scrollText(_ command: Selector) {
    textView.doCommand(by: command)
  }

  func placeDescription(ofBlock block: Int) -> String {
    let rows = content.blocks[block].rows
    let lines = content.lineNumbers
    if rows.isEmpty {
      // A block without rows lies after the line before it.
      guard let line = lines[..<min(rows.lowerBound, lines.count)].last(where: { $0 >= 0 }) else {
        return String(
          localized: "Before the first line", bundle: .module,
          comment: "VoiceOver: where a mark beside filler rows at the start is.")
      }
      return String(
        localized: "After line \(Int(line) + 1)", bundle: .module,
        comment: "VoiceOver: where a mark beside a filler row is.")
    }
    let line = lines[...rows.lowerBound].last { $0 >= 0 }.map { Int($0) + 1 } ?? 1
    return String(
      localized: "Line \(line)", bundle: .module, comment: "VoiceOver: where a mark is.")
  }
}
