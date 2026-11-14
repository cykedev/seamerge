import AppKit

extension PaneTextView {
  /// The offset of the first change of `block`: its first changed run, or the start of its
  /// first row if the highlight provider knows no runs.
  func firstChangeOffset(ofBlock block: Int) -> Int {
    let firstRow = min(content.blocks[block].rows.lowerBound, grid.rowCount - 1)
    return highlights(forBlock: block).first?.lowerBound ?? grid.offsets(ofRow: firstRow).lowerBound
  }

  /// Scrolls so that the character at `offset` comes into view with some text before it, unless
  /// it is in view already: the way of a jump and of the find bar.
  ///
  /// A row that comes into view vertically comes to rest at the reading line. Sideways, the view
  /// goes back to the start of the lines if the place fits within the first screen width.
  func reveal(offset: Int) {
    scroll(toShow: offset, withContext: true)
  }

  /// Brings a range into view: a result of the find bar the way a jump does, the selection that
  /// the user moves in this view by as little as it takes, as in any text view.
  override func scrollRangeToVisible(_ range: NSRange) {
    guard range.location != NSNotFound else { return }
    // The find bar has the focus while it searches as the user types; Find Next runs as an action.
    let isFindResult = isPerformingFindAction || window?.firstResponder !== self
    scroll(toShow: min(range.location, grid.textLength), withContext: isFindResult)
  }

  override func performTextFinderAction(_ sender: Any?) {
    isPerformingFindAction = true
    defer { isPerformingFindAction = false }
    super.performTextFinderAction(sender)
  }

  override func performFindPanelAction(_ sender: Any?) {
    isPerformingFindAction = true
    defer { isPerformingFindAction = false }
    super.performFindPanelAction(sender)
  }

  private func scroll(toShow offset: Int, withContext: Bool) {
    // A place behind a bar comes into view once its run is expanded; until then the bar shows.
    if let run = displayRows.runIndex(containingRow: grid.row(containingOffset: offset)) {
      interaction?.askToExpandRun(at: run)
    }
    guard
      let scrollView = enclosingScrollView,
      let origin = origin(
        showing: offset, in: scrollView.contentView.bounds, withContext: withContext)
    else { return }
    scrollView.contentView.scroll(to: origin)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  /// The origin of the visible part that shows the character at `offset`, or `nil` if `visible`
  /// shows it already.
  ///
  /// With `withContext`, a row that comes into view rests at the reading line and the character
  /// has some text before it; without, the view moves only as far as it takes.
  private func origin(showing offset: Int, in visible: CGRect, withContext: Bool) -> CGPoint? {
    let row = grid.row(containingOffset: offset)
    let (x, line) = position(ofOffset: offset)
    let place = CGRect(
      x: x,
      y: CGFloat(displayRows.lines(ofRows: row..<row + 1).lowerBound + line) * theme.rowHeight,
      width: theme.characterWidth, height: theme.rowHeight)
    var origin = visible.origin
    if place.minY < visible.minY || place.maxY > visible.maxY {
      let y =
        withContext
        ? place.minY - Theme.readingLine * visible.height
        : place.minY < visible.minY ? place.minY : place.maxY - visible.height
      origin.y = min(max(y, 0), max(frame.height - visible.height, 0)).rounded()
    }
    if place.minX < visible.minX || place.maxX > visible.maxX {
      let x: CGFloat
      if withContext {
        let context = CGFloat(Theme.revealContextColumns) * theme.characterWidth
        x = place.maxX + context <= visible.width ? 0 : place.minX - context
      } else {
        x = place.minX < visible.minX ? place.minX : place.maxX - visible.width
      }
      origin.x = min(max(x, 0), max(frame.width - visible.width, 0)).rounded()
    }
    return origin == visible.origin ? nil : origin
  }

  /// The distance from the left edge of the view to the character at `offset`, and the screen
  /// line of its row that the character is on.
  ///
  /// Lays out the paragraph of the character, and only that one.
  private func position(ofOffset offset: Int) -> (x: CGFloat, line: Int) {
    let lineStart = (textContainerOrigin.x, 0)
    guard let textLayoutManager else { return lineStart }
    let row = grid.row(containingOffset: offset)
    let paragraph = grid.paragraphOffsets(ofRows: row..<row + 1)
    let documentStart = textLayoutManager.documentRange.location
    guard
      let location = textLayoutManager.location(documentStart, offsetBy: offset),
      let start = textLayoutManager.location(documentStart, offsetBy: paragraph.lowerBound),
      let end = textLayoutManager.location(documentStart, offsetBy: paragraph.upperBound),
      let range = NSTextRange(location: start, end: end)
    else { return lineStart }
    textLayoutManager.ensureLayout(for: range)
    guard
      let fragment = textLayoutManager.textLayoutFragment(for: location) as? RowLayoutFragment
    else { return lineStart }
    let index = offset - fragment.paragraphStart
    let lines = fragment.textLineFragments
    guard
      let lineIndex = lines.firstIndex(where: {
        $0.characterRange.lowerBound <= index && index <= $0.characterRange.upperBound
      })
    else { return lineStart }
    let line = lines[lineIndex]
    let x =
      textContainerOrigin.x + fragment.layoutFragmentFrame.minX + line.typographicBounds.minX
      + line.locationForCharacter(at: index).x
    return (x, fragment.rowIndex(of: line) == 0 ? lineIndex : 0)
  }
}
