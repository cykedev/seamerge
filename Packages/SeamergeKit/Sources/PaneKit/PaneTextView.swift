import AppKit

/// The text view of a pane: read-only text on the row grid, drawn with TextKit 2.
///
/// Selection, copying, the find bar, input methods and VoiceOver come from `NSTextView`. The
/// view adds the row fills, the highlights and marks within lines and its size, all from the
/// grid rather than from TextKit, so that row *r* lies at `r × rowHeight` in every pane. Its
/// fragments draw the selection, translucent above the row fills (see `RowLayoutFragment`).
final class PaneTextView: NSTextView {
  private(set) var theme = Theme()
  private(set) var content = PaneContent.empty
  private(set) var currentBlock: Int?
  private var grid = RowGrid(text: "", tabWidth: 1)

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
    NotificationCenter.default.addObserver(
      self, selector: #selector(willSwitchToLayoutManager(_:)),
      name: NSTextView.willSwitchToNSLayoutManagerNotification, object: self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionDidChange(_:)),
      name: NSTextView.didChangeSelectionNotification, object: self)
    self.theme = theme
  }

  /// Shows `content` drawn with `theme`.
  ///
  /// - Precondition: `content` has one line number per row.
  func show(_ content: PaneContent, theme: Theme) {
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

  /// Marks the block at `block` as the current one, or none.
  func setCurrentBlock(_ block: Int?) {
    guard block != currentBlock else { return }
    let previous = currentBlock
    currentBlock = block
    for index in [previous, block].compactMap(\.self) where content.blocks.indices.contains(index) {
      redraw(rows: content.blocks[index].rows)
    }
  }

  /// The size that the view needs for its rows, at least as wide as `visibleWidth`.
  func fittingSize(visibleWidth: CGFloat) -> CGSize {
    let textWidth = CGFloat(grid.widestRowColumns) * theme.characterWidth + 2 * Theme.textInset
    return CGSize(
      width: max(visibleWidth, textWidth.rounded(.up)),
      height: CGFloat(grid.rowCount) * theme.rowHeight)
  }

  /// The origin of the text, fixed by the inset.
  ///
  /// `NSTextView` would derive it from the extent of the laid-out text, and to find that, lay
  /// out the whole document whenever the view's geometry changes.
  override var textContainerOrigin: NSPoint {
    NSPoint(x: textContainerInset.width, y: textContainerInset.height)
  }

  override func becomeFirstResponder() -> Bool {
    defer { redraw(selections: selectedRanges) }
    return super.becomeFirstResponder()
  }

  override func resignFirstResponder() -> Bool {
    defer { redraw(selections: selectedRanges) }
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

  @objc private func selectionDidChange(_ notification: Notification) {
    redraw(selections: drawnSelection + selectedRanges)
    drawnSelection = selectedRanges
  }

  @objc private func windowKeyStateDidChange(_ notification: Notification) {
    redraw(selections: selectedRanges)
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

  private func highlights(forBlock block: Int) -> [Range<Int>] {
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

extension PaneTextView: RowPainter {
  var extent: RowLayoutFragment.Extent {
    RowLayoutFragment.Extent(
      containerInset: textContainerOrigin.x, width: bounds.width, textLift: theme.textLift,
      removalMarkWidth: Theme.removalMarkWidth, removalMarkSeam: Theme.markSeam)
  }

  func painting(forRows rows: Range<Int>) -> RowLayoutFragment.Painting {
    let changes = changes(inRows: rows)
    let paragraph = grid.paragraphOffsets(ofRows: rows)
    let selectionFill = theme.selectionFill(isEmphasized: isSelectionEmphasized)
    let selections = selectedRanges.map(\.rangeValue).compactMap { selection in
      let range = selection.location..<selection.location + selection.length
      return range.isEmpty || !range.overlaps(paragraph)
        ? nil : RowLayoutFragment.Run(range: range, fill: selectionFill)
    }
    return RowLayoutFragment.Painting(
      extent: extent, rowFills: rows.map(rowFill(atRow:)), background: Theme.backgroundColor,
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
