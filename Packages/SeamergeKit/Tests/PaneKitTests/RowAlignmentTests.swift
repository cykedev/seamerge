import AppKit
import Testing

@testable import PaneKit

/// Checks that panes on the same grid keep every row level while their lines wrap, at any width
/// and with wrapping on or off, that the insertion point and the selection move through the
/// screen lines of a wrapped row, and that a block's row in the decision column stands beside
/// the first screen line of the block.
@MainActor
@Suite struct RowAlignmentTests {
  @Test(arguments: [true, false], [CGFloat(900), 1_500])
  func everyRowStartsAndEndsAtTheSameHeightInEveryPane(wraps: Bool, width: CGFloat) throws {
    let (panes, window) = Self.alignedPanes(width: width, wraps: wraps)
    defer { window.close() }
    let rowCount = panes[0].content.lineNumbers.count
    if wraps && width < 1_000 {
      #expect(panes[0].displayRows.lineCount > rowCount, "some rows wrap")
    } else if !wraps {
      #expect(panes.allSatisfy { $0.displayRows.lineCount == rowCount })
    }
    for row in 0..<rowCount {
      let spans = panes.map { $0.verticalSpan(ofRows: row..<row + 1) }
      #expect(spans.allSatisfy { $0 == spans[0] }, "row \(row): \(spans)")
      let gutterRects = panes.map { $0.gutterView.rect(ofRow: row) }
      #expect(gutterRects.allSatisfy { $0.minY == gutterRects[0].minY }, "row \(row)")
      #expect(gutterRects.allSatisfy { $0.height == gutterRects[0].height }, "row \(row)")
    }
    for pane in panes {
      let manager = try #require(pane.textView.textLayoutManager)
      manager.ensureLayout(for: manager.documentRange)
      var laidOutRows = 0
      manager.enumerateTextLayoutFragments(from: manager.documentRange.location) { fragment in
        guard let fragment = fragment as? RowLayoutFragment else { return false }
        let span = pane.verticalSpan(ofRows: fragment.rows)
        let frame = fragment.layoutFragmentFrame
        #expect(frame.minY == span.lowerBound && frame.maxY == span.upperBound, "\(fragment.rows)")
        laidOutRows += fragment.rows.count
        return true
      }
      #expect(laidOutRows == rowCount)
    }
    let heights = panes.map(\.documentView.frame.height)
    #expect(heights.allSatisfy { $0 == heights[0] })
  }

  @Test func rowsLineUpAgainWhenAPaneGetsLongerLines() {
    let (panes, window) = Self.alignedPanes(width: 900, wraps: true)
    defer { window.close() }
    let before = panes[0].verticalSpan(ofRows: 1..<2)
    var content = panes[2].content
    var lines = content.text.components(separatedBy: "\n")
    lines[1] = String(repeating: "longer words ", count: 30)
    content.text = lines.joined(separator: "\n")
    panes[2].content = content
    window.contentView?.layoutSubtreeIfNeeded()
    let after = panes.map { $0.verticalSpan(ofRows: 1..<2) }
    #expect(after.allSatisfy { $0 == after[0] })
    #expect(after[0].upperBound > before.upperBound)
  }

  @Test func insertionPointMovesThroughTheScreenLinesOfAWrappedRow() throws {
    let long = String(repeating: "word ", count: 40)
    let (pane, window, _) = EditingTests.editablePane(
      text: "first\n\(long)\nlast", size: CGSize(width: 420, height: 400))
    defer { window.close() }
    pane.wrapsLines = true
    window.contentView?.layoutSubtreeIfNeeded()
    let textView = pane.textView
    let lines = pane.displayRows.lines(ofRows: 1..<2).count
    try #require(lines >= 3)
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    var rowsVisited: [Int] = []
    for _ in 0..<lines + 1 {
      textView.moveDown(nil)
      rowsVisited.append(textView.grid.row(containingOffset: textView.selectedRange().location))
    }
    #expect(rowsVisited == Array(repeating: 1, count: lines) + [2], "\(rowsVisited)")
    // Moving up from the last row passes every screen line of the wrapped row again.
    var offsets: [Int] = []
    for _ in 0..<lines {
      textView.moveUp(nil)
      offsets.append(textView.selectedRange().location)
    }
    #expect(offsets.allSatisfy { textView.grid.row(containingOffset: $0) == 1 }, "\(offsets)")
    #expect(offsets == offsets.sorted(by: >))
    // The selection grows a screen line at a time.
    textView.setSelectedRange(
      NSRange(location: textView.grid.offsets(ofRow: 1).lowerBound, length: 0))
    textView.moveDownAndModifySelection(nil)
    let selection = textView.selectedRange()
    #expect(selection.length > 0)
    #expect(textView.grid.row(containingOffset: selection.location + selection.length) == 1)
  }

  @Test func typingThatMakesARowWrapMovesTheRowsBelowDown() throws {
    let (pane, window, recorder) = EditingTests.editablePane(
      text: "short\nlast", size: CGSize(width: 420, height: 400))
    defer { window.close() }
    // The pane holds its editing delegate weakly.
    defer { withExtendedLifetime(recorder) {} }
    pane.wrapsLines = true
    window.contentView?.layoutSubtreeIfNeeded()
    let textView = pane.textView
    let lastRowTop = pane.verticalSpan(ofRows: 1..<2).lowerBound
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    textView.insertText(
      String(repeating: " more", count: 30),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    window.contentView?.layoutSubtreeIfNeeded()
    let lines = pane.displayRows.lines(ofRows: 0..<1).count
    #expect(lines > 1)
    #expect(
      pane.verticalSpan(ofRows: 1..<2).lowerBound
        == lastRowTop + CGFloat(lines - 1) * pane.theme.rowHeight)
    let manager = try #require(textView.textLayoutManager)
    manager.ensureLayout(for: manager.documentRange)
    let fragment = try #require(Self.fragment(ofRow: 0, in: textView))
    #expect(fragment.textLineFragments.count == lines)
  }

  @Test func blockRowStandsBesideTheFirstScreenLineOfTheBlock() {
    let pane = PaneView()
    pane.wrapsLines = true
    let long = String(repeating: "word ", count: 40)
    pane.content = PaneContent(
      text: "\(long)\n\(long)\nend", lineNumbers: [0, 1, 2],
      blocks: [PaneBlock(rows: 1..<2, style: .tinted(.a), marker: .changed)])
    let window = Rendering.host(pane, size: CGSize(width: 420, height: 400))
    defer { window.close() }
    let span = pane.verticalSpan(ofRows: 1..<2)
    #expect(span.upperBound - span.lowerBound > 2 * pane.theme.rowHeight)
    #expect(pane.rowCenter(ofBlock: 0) == span.lowerBound + pane.theme.rowHeight / 2)
  }

  /// Three panes side by side on one grid, of different widths, each with long lines in other
  /// rows, lined up by an alignment.
  static func alignedPanes(width: CGFloat, wraps: Bool) -> ([PaneView], NSWindow) {
    let short = "let value = 1"
    let long = "let message = " + String(repeating: "\"words that run on\" + ", count: 8) + "\"\""
    let texts = [
      [short, long, short, short, long, "", short],
      [short, short, long + long, short, short, "", short],
      [long, short, short, short, long, "", ""],
    ]
    let container = SideBySide()
    let alignment = RowAlignment()
    let panes = texts.map { lines in
      let pane = PaneView()
      pane.wrapsLines = wraps
      pane.content = PaneContent(
        text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map(Int32.init))
      container.addSubview(pane)
      alignment.add(pane)
      return pane
    }
    container.alignment = alignment
    let window = Rendering.host(container, size: CGSize(width: width, height: 900))
    return (panes, window)
  }

  static func fragment(ofRow row: Int, in textView: PaneTextView) -> NSTextLayoutFragment? {
    guard let manager = textView.textLayoutManager else { return nil }
    let offset = textView.grid.offsets(ofRow: row).lowerBound
    guard let location = manager.location(manager.documentRange.location, offsetBy: offset)
    else { return nil }
    return manager.textLayoutFragment(for: location)
  }

  /// Lays out its panes side by side, the first a quarter, the others three eighths of the width.
  final class SideBySide: NSView {
    var alignment: RowAlignment?

    override func layout() {
      super.layout()
      let fractions: [CGFloat] = [0.25, 0.375, 0.375]
      var x: CGFloat = 0
      for (pane, fraction) in zip(subviews, fractions) {
        pane.frame = CGRect(
          x: x, y: 0, width: (bounds.width * fraction).rounded(), height: bounds.height)
        x += pane.frame.width
      }
    }
  }
}
