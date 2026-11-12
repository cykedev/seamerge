import AppKit

/// The text view of a pane: read-only text on the row grid, drawn with TextKit 2.
///
/// Selection, copying, the find bar, input methods and VoiceOver come from `NSTextView`. The
/// view adds the row fills, the highlights and marks within lines and its size, all from the
/// grid rather than from TextKit, so that row *r* lies at its display row times `rowHeight` in
/// every pane; the rows behind a collapsed run take no room, except the one of its bar. Its
/// fragments draw the selection, translucent above the row fills (see `RowLayoutFragment`).
final class PaneTextView: NSTextView {
  private(set) var theme = Theme()
  private(set) var content = PaneContent.empty
  private(set) var currentBlock: Int?
  private(set) var grid = RowGrid(text: "", tabWidth: 1)
  private(set) var displayRows = DisplayRows(runs: [], rowCount: 1)

  /// Learns about clicks on rows and supplies the context menu.
  weak var interaction: (any RowInteraction)?

  /// Whether a find action of the find bar or the Find menu is under way, whose result comes into
  /// view the way a jump does.
  var isPerformingFindAction = false

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

  /// The selection as the fragments last drew it.
  private var drawnSelection: [NSValue] = []

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
    NotificationCenter.default.addObserver(
      self, selector: #selector(willSwitchToLayoutManager(_:)),
      name: NSTextView.willSwitchToNSLayoutManagerNotification, object: self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionDidChange(_:)),
      name: NSTextView.didChangeSelectionNotification, object: self)
    self.theme = theme
  }

  /// Shows `content` with `collapsedRuns`, drawn with `theme`.
  ///
  /// - Precondition: `content` has one line number per row, and the runs lie within its rows.
  func show(_ content: PaneContent, collapsedRuns: [CollapsedRun], theme: Theme) {
    let grid = RowGrid(text: content.text, tabWidth: theme.tabWidth)
    precondition(
      content.lineNumbers.count == grid.rowCount,
      "\(content.lineNumbers.count) line numbers for \(grid.rowCount) rows")
    precondition(
      content.lineEndings.count == grid.rowCount,
      "\(content.lineEndings.count) line endings for \(grid.rowCount) rows")
    self.content = content
    self.theme = theme
    self.grid = grid
    displayRows = DisplayRows(runs: collapsedRuns, rowCount: grid.rowCount)
    if let currentBlock, !content.blocks.indices.contains(currentBlock) {
      self.currentBlock = nil
    }
    highlightsByBlock.removeAll()
    let attributes = textAttributes
    font = theme.font
    defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
    typingAttributes = attributes
    textStorage?.setAttributedString(
      NSAttributedString(string: content.text, attributes: attributes))
  }

  /// Hides `runs` of rows behind bars, each one row high, and lays out the text again.
  ///
  /// - Precondition: The runs are sorted, do not overlap and lie within the rows.
  func setCollapsedRuns(_ runs: [CollapsedRun]) {
    guard runs != displayRows.runs else { return }
    displayRows = DisplayRows(runs: runs, rowCount: grid.rowCount)
    guard let textLayoutManager else { return }
    // Which paragraphs the layout manager enumerates changes with the runs.
    textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
    needsDisplay = true
  }

  /// Marks the block at `block` as the current one, or none.
  func setCurrentBlock(_ block: Int?) {
    guard block != currentBlock else { return }
    let previous = currentBlock
    currentBlock = block
    for index in [previous, block].compactMap(\.self) where content.blocks.indices.contains(index) {
      redraw(rows: content.blocks[index].rows)
    }
  }

  /// The width that the widest row needs, known before TextKit lays it out, so that the scroll
  /// range does not grow while the user scrolls.
  var textWidth: CGFloat {
    (CGFloat(grid.widestRowColumns) * theme.characterWidth + 2 * Theme.textInset).rounded(.up)
  }

  /// The origin of the text, fixed by the inset.
  ///
  /// `NSTextView` would derive it from the extent of the laid-out text, and to find that, lay
  /// out the whole document whenever the view's geometry changes.
  override var textContainerOrigin: NSPoint {
    NSPoint(x: textContainerInset.width, y: textContainerInset.height)
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
    let displayRow = Int((point.y / theme.rowHeight).rounded(.down))
    return displayRows.row(atDisplayRow: min(max(displayRow, 0), displayRows.count - 1))
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
    // The fragments fill their rows to the width of the view when they are created.
    if widthChanged, let textLayoutManager {
      textLayoutManager.invalidateLayout(for: textLayoutManager.documentRange)
    }
  }

  /// The attributes of all text: one font, rows of the grid's height, no wrapping.
  private var textAttributes: [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = theme.rowHeight
    paragraph.maximumLineHeight = theme.rowHeight
    paragraph.lineBreakMode = .byClipping
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
  private var isSelectionEmphasized: Bool {
    guard let window else { return false }
    return window.isKeyWindow && window.firstResponder === self
  }

  /// The fill of the selection as the fragments draw it now.
  var selectionFill: NSColor {
    theme.selectionFill(isEmphasized: isSelectionEmphasized)
  }

  @objc private func selectionDidChange(_ notification: Notification) {
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

  private func redraw(rows: Range<Int>) {
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
  }

  /// The fill of `row`, or `nil` if it stays on the text background.
  private func rowFill(atRow row: Int) -> NSColor? {
    let blockIndex = content.blockIndex(atRow: row)
    return theme.rowFill(
      for: blockIndex.map { content.blocks[$0].style } ?? .unchanged,
      isFiller: content.isFiller(row: row),
      isCurrent: blockIndex != nil && blockIndex == currentBlock)
  }

  /// The changed runs within `rows` with their fills, and the places of removed text with the
  /// colors of their marks.
  private func changes(inRows rows: Range<Int>) -> (
    runs: [RowLayoutFragment.Run], removals: [RowLayoutFragment.Removal]
  ) {
    var runs: [RowLayoutFragment.Run] = []
    var removals: [RowLayoutFragment.Removal] = []
    for row in rows {
      guard let blockIndex = content.blockIndex(atRow: row) else { continue }
      let style = content.blocks[blockIndex].style
      let rowOffsets = grid.paragraphOffsets(ofRows: row..<row + 1)
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
    let documentStart = textLayoutManager.documentRange.location
    let start = textLayoutManager.offset(from: documentStart, to: location)
    let end =
      textElement.elementRange.map {
        textLayoutManager.offset(from: documentStart, to: $0.endLocation)
      } ?? start
    return RowLayoutFragment(
      textElement: textElement, range: textElement.elementRange, paragraphStart: start,
      rows: grid.rows(ofParagraphFrom: start, to: end), rowHeight: theme.rowHeight,
      painter: self)
  }
}

extension PaneTextView: @MainActor NSTextContentStorageDelegate {
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
  func displayRows(ofRows rows: Range<Int>) -> Range<Int> {
    displayRows.displayRows(ofRows: rows)
  }

  var extent: RowLayoutFragment.Extent {
    RowLayoutFragment.Extent(
      containerInset: textContainerOrigin.x, width: bounds.width, textLift: theme.textLift,
      removalMarkWidth: Theme.removalMarkWidth, removalMarkSeam: Theme.markSeam)
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
      rowFills: rows.map(rowFill(atRow:)), background: Theme.backgroundColor,
      textBandHeight: theme.textBandHeight, runs: changes.runs, selections: selections,
      removals: changes.removals,
      invisibles: showsInvisibles
        ? RowLayoutFragment.Invisibles(
          lineEndings: Array(content.lineEndings[rows]),
          color: theme.invisibleCharacterColor, baseline: theme.baseline) : nil)
  }
}

extension Array {
  /// The index of the first element for which `belongs` holds, in an array where it holds for
  /// a suffix of the elements, or `endIndex` if it holds for none.
  fileprivate func partitioningIndex(where belongs: (Element) -> Bool) -> Int {
    var low = startIndex
    var high = endIndex
    while low < high {
      let middle = (low + high) / 2
      if belongs(self[middle]) {
        high = middle
      } else {
        low = middle + 1
      }
    }
    return low
  }
}
