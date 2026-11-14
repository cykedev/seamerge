import AppKit
import MergeModel
import PaneKit

extension SessionPresentation {
  /// The text of the input of `role` without filler rows, made once.
  func lineText(of role: Role) -> DisplayText {
    if let text = lineTexts[role] {
      return text
    }
    guard let text = changes.session.rowLayout.lineText(for: role) else {
      preconditionFailure("The session has no input \(role)")
    }
    lineTexts[role] = text
    return text
  }

  /// The map from rows of the grid to lines of the input of `role`.
  func gridMap(of role: Role) -> ScrollMap {
    ScrollMap(session: changes.session, from: .grid, to: .lines(role))
  }

  /// Couples neighboring panes side by side block by block, while they show the lines of their
  /// files, so that the block at the reading line of one stands at the reading line of the
  /// other; on the grid, they share one origin.
  func connectSourcePanes() {
    let panes = layout.sourcePanes
    for (left, right) in zip(panes, panes.dropFirst()) {
      guard !alignsLines else {
        scrollSync.removeRowMapping(between: left.pane, and: right.pane)
        continue
      }
      let map = ScrollMap(
        session: changes.session, from: .lines(left.role), to: .lines(right.role))
      scrollSync.setRowMapping(
        between: left.pane, and: right.pane, forward: { map.targetPosition(at: $0) },
        backward: { map.sourcePosition(at: $0) })
    }
  }

  /// Lets the overview bar of the panes side by side measure on the grid while its pane shows
  /// the lines of its file, so that its marks stand where they stand on the grid and its frame
  /// shows the visible part converted to the grid; on the grid, it measures its pane's rows.
  func showOverviewGrid() {
    guard let (role, pane) = layout.sourcePanes.last else { return }
    guard !alignsLines else {
      pane.overviewGrid = nil
      return
    }
    let map = gridMap(of: role)
    pane.overviewGrid = OverviewGrid(
      rowCount: changes.session.rowLayout.rowCount,
      collapsedRuns: collapsed.runs.map { CollapsedRun(rows: $0.rows) },
      gridRow: { map.sourcePosition(at: $0) }, paneRow: { map.targetPosition(at: $0) })
  }

  /// The pane side by side in view with the most lines in `block`, which leads when the panes
  /// that show the lines of their files scroll to the block or read the place at the reading
  /// line: it spreads its lines over the rows of the block one for one, and a pane without lines
  /// there would put the boundary at the reading line rather than the block.
  ///
  /// Among panes with as many lines, B leads, as the side that Go to Line and the overview bar
  /// follow; then the panes from left to right.
  func paneWithMostLines(in block: Block) -> (role: Role, pane: PaneView)? {
    layout.sourcePanes.filter(\.pane.isShown).min { first, second in
      let (firstLines, secondLines) = (
        block.lines(in: first.role).count, block.lines(in: second.role).count
      )
      guard firstLines == secondLines else { return firstLines > secondLines }
      return first.role == .b && second.role != .b
    }
  }

  /// The place at the reading line as a row of the grid with its fraction, or `nil` without a
  /// pane side by side in view.
  ///
  /// While the panes show the lines of their files and scroll together, the place is the
  /// earliest that any of them reads: a pane without lines in the block at the reading line
  /// stands on the boundary where they are missing, which lies at the end of the block on the
  /// grid. Each pane on its own, B tells the place.
  var gridPlaceAtReadingLine: Double? {
    let shown = layout.sourcePanes.filter(\.pane.isShown)
    guard let first = shown.first else { return nil }
    if alignsLines {
      let (row, fraction) = first.pane.rowAtReadingLine
      return Double(row) + Double(fraction)
    }
    func gridPosition(in source: (role: Role, pane: PaneView)) -> Double {
      let (row, fraction) = source.pane.rowAtReadingLine
      return gridMap(of: source.role).sourcePosition(at: Double(row) + Double(fraction))
    }
    guard scrollSync.isEnabled else {
      return gridPosition(in: shown.first { $0.role == .b } ?? first)
    }
    return shown.map(gridPosition(in:)).min()
  }

  /// Scrolls the panes side by side so that `place`, a row of the grid with its fraction, comes
  /// to the reading line, led by the pane with the most lines in the block there.
  func scroll(toGridPlace place: Double) {
    let rowLayout = changes.session.rowLayout
    guard rowLayout.rowCount > 0 else { return }
    let shown = layout.sourcePanes.filter(\.pane.isShown)
    if alignsLines {
      guard let pane = shown.first?.pane else { return }
      let row = min(max(Int(place), 0), rowLayout.rowCount - 1)
      pane.scroll(
        toPlaceRowAtReadingLine: row, fraction: CGFloat(place - Double(row)), motion: .cut)
      return
    }
    let block = rowLayout.block(atRow: min(max(Int(place), 0), rowLayout.rowCount - 1))
    let panes = scrollSync.isEnabled ? [paneWithMostLines(in: block)].compactMap(\.self) : shown
    for (role, pane) in panes {
      let lineCount = rowLayout.lineCount(in: role)
      guard lineCount > 0 else { continue }
      let position = min(max(gridMap(of: role).targetPosition(at: place), 0), Double(lineCount))
      let line = min(Int(position), lineCount - 1)
      pane.scroll(
        toPlaceRowAtReadingLine: line, fraction: CGFloat(position - Double(line)), motion: .cut)
    }
  }

  /// `range` of the text of the pane of `role` as lines of its file and places within them,
  /// whether the pane shows the grid or not.
  func textRange(_ range: NSRange, in role: Role) -> (start: TextPlace, end: TextPlace) {
    (
      textPlace(atOffset: range.location, in: role),
      textPlace(atOffset: range.location + range.length, in: role)
    )
  }

  /// The range of the text of the pane of `role` as it shows the input now that `range` names.
  func paneRange(_ range: (start: TextPlace, end: TextPlace), in role: Role) -> NSRange {
    let start = offset(of: range.start, in: role)
    let end = max(offset(of: range.end, in: role), start)
    return NSRange(location: start, length: end - start)
  }

  /// The place of the UTF-16 `offset` of the text of the pane of `role`; on a filler row, the
  /// start of the line after it.
  private func textPlace(atOffset offset: Int, in role: Role) -> TextPlace {
    let rowLayout = changes.session.rowLayout
    guard let text = alignsLines ? rowLayout.displayText(for: role) : lineText(of: role),
      text.rowCount > 0
    else { return TextPlace(line: 0, column: 0) }
    let row = rowLayout.rowCount > 0 ? row(containingOffset: offset, in: text) : 0
    let column = offset - text.utf16Range(ofRow: row).lowerBound
    guard alignsLines else { return TextPlace(line: row, column: column) }
    if let line = rowLayout.line(atRow: row, in: role) {
      return TextPlace(line: line, column: column)
    }
    let next = (row..<rowLayout.rowCount).lazy.compactMap { rowLayout.line(atRow: $0, in: role) }
    return TextPlace(line: next.first ?? rowLayout.lineCount(in: role), column: 0)
  }

  /// The UTF-16 offset of `place` in the text of the pane of `role` as it shows the input now;
  /// a place beyond the text lies at its end.
  private func offset(of place: TextPlace, in role: Role) -> Int {
    let rowLayout = changes.session.rowLayout
    let lineCount = rowLayout.lineCount(in: role)
    guard let text = alignsLines ? rowLayout.displayText(for: role) : lineText(of: role),
      lineCount > 0
    else { return 0 }
    guard place.line < lineCount else {
      return text.utf16Range(ofRow: text.rowCount - 1).upperBound
    }
    let row = alignsLines ? rowLayout.row(ofLine: place.line, in: role) : place.line
    let range = text.utf16Range(ofRow: row)
    return range.lowerBound + min(place.column, range.count)
  }

  /// The row of `text` that the UTF-16 `offset` lies in; the end of the text lies in the last.
  private func row(containingOffset offset: Int, in text: DisplayText) -> Int {
    var low = 0
    var high = text.rowCount
    while high - low > 1 {
      let middle = (low + high) / 2
      if text.utf16Range(ofRow: middle).lowerBound <= offset { low = middle } else { high = middle }
    }
    return low
  }
}

/// A place in the text of an input: a line of its file and a UTF-16 offset within the line.
struct TextPlace {
  var line: Int
  var column: Int
}
