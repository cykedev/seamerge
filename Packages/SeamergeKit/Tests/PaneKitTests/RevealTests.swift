import AppKit
import PaneKit
import Testing

/// Checks how a pane brings a place into view: a jump to a block, a find result, the selection;
/// and that nothing else moves the text once the user has scrolled.
@MainActor
@Suite struct RevealTests {
  @Test func jumpShowsTheFirstChangeOfABlockWithSomeTextBeforeIt() throws {
    let (pane, window, provider) = Self.pane(changeAtColumn: 150)
    defer { window.close() }
    pane.reveal(block: 0)
    let visible = pane.documentView.visibleRect
    let theme = pane.theme
    let changeX = Self.textInset + 150 * Self.characterWidth(theme)
    #expect(abs(changeX - visible.minX - 8 * Self.characterWidth(theme)) < 1)
    // The row of the change rests at the reading line, a quarter down.
    #expect(visible.minY == (Self.blockRow * theme.rowHeight - 0.25 * visible.height).rounded())
    _ = provider
  }

  @Test func jumpMovesNothingWhenTheChangeIsInView() throws {
    let (pane, window, provider) = Self.pane(changeAtColumn: 150)
    defer { window.close() }
    pane.reveal(block: 0)
    let first = pane.documentView.visibleRect.origin
    pane.documentView.scroll(CGPoint(x: first.x - 40, y: first.y - 60))
    let moved = pane.documentView.visibleRect.origin
    pane.reveal(block: 0)
    #expect(pane.documentView.visibleRect.origin == moved)
    _ = provider
  }

  @Test func changeNearTheStartOfItsLineIsShownWithTheWholeStart() throws {
    let (pane, window, provider) = Self.pane(changeAtColumn: 12)
    defer { window.close() }
    pane.documentView.scroll(CGPoint(x: 600, y: 0))
    pane.reveal(block: 0)
    #expect(pane.documentView.visibleRect.minX == 0)
    _ = provider
  }

  @Test func findResultComesIntoViewLikeAJump() throws {
    let (pane, window, provider) = Self.pane(changeAtColumn: 150)
    defer { window.close() }
    pane.reveal(block: 0)
    let jump = pane.documentView.visibleRect.origin
    pane.documentView.scroll(.zero)
    // The find bar has the focus while it brings its result into view this way.
    let offset = CodeRows.start(ofRow: Int(Self.blockRow), length: Self.length) + 150
    pane.documentView.scrollRangeToVisible(NSRange(location: offset, length: 6))
    #expect(pane.documentView.visibleRect.origin == jump)
    _ = provider
  }

  @Test func selectionInThePartlyVisibleLastRowMovesTheTextOnlyAsFarAsItTakes() throws {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 1_000, length: 300)
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 290))
    defer { window.close() }
    let textView = pane.documentView
    window.makeFirstResponder(textView)
    textView.scroll(CGPoint(x: 120, y: 400))
    let before = textView.visibleRect
    let rowHeight = pane.theme.rowHeight
    let lastRow = Int((before.maxY / rowHeight).rounded(.down))
    try #require(CGFloat(lastRow + 1) * rowHeight > before.maxY, "the last row is cut off")
    // A click selects in the row and has the text view bring the selection into view.
    let offset = CodeRows.start(ofRow: lastRow, length: 300) + 20
    textView.setSelectedRange(NSRange(location: offset, length: 0))
    textView.scrollRangeToVisible(textView.selectedRange())
    let after = textView.visibleRect
    #expect(after.maxY == CGFloat(lastRow + 1) * rowHeight, "the row just comes into view")
    #expect(after.minY - before.minY < rowHeight)
    #expect(after.minX == before.minX)
  }

  @Test func extendingTheSelectionAtTheEdgeMovesTheTextByARowAtMost() throws {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 1_000, length: 60)
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 290))
    defer { window.close() }
    let textView = pane.documentView
    window.makeFirstResponder(textView)
    textView.scroll(CGPoint(x: 0, y: 400))
    let before = textView.visibleRect
    let rowHeight = pane.theme.rowHeight
    let lastRow = Int((before.maxY / rowHeight).rounded(.down))
    let offset = CodeRows.start(ofRow: lastRow - 1, length: 60) + 4
    textView.setSelectedRange(NSRange(location: offset, length: 0))
    textView.moveDownAndModifySelection(nil)
    textView.moveDownAndModifySelection(nil)
    let after = textView.visibleRect
    #expect(after.minY > before.minY, "the selection pulls the text along")
    #expect(after.minY - before.minY <= 2 * rowHeight)
  }

  @Test func coupledPanesFollowAJump() throws {
    let layout = CoupledLayout(merge: .transcoder, repeats: 12, theme: Theme())
    let window = Rendering.host(layout, size: CGSize(width: 900, height: 600))
    defer { window.close() }
    let last = layout.upperPanes[2].content.blocks.count - 1
    layout.upperPanes[2].reveal(block: last)
    let origin = layout.upperPanes[2].documentView.visibleRect.origin
    #expect(origin.y > 0)
    for pane in layout.upperPanes {
      #expect(pane.documentView.visibleRect.origin == origin)
    }
  }

  @Test func nothingMovesTheTextAfterTheUserScrolled() throws {
    let (pane, window, provider) = Self.pane(changeAtColumn: 150)
    defer { window.close() }
    pane.documentView.scroll(CGPoint(x: 230, y: 410))
    let origin = pane.documentView.visibleRect.origin
    pane.currentBlock = 0
    pane.highlightProvider = provider
    pane.showsInvisibles = true
    let (theme, content) = (pane.theme, pane.content)
    pane.theme = theme
    pane.content = content
    pane.documentView.setSelectedRange(NSRange(location: 5, length: 10))
    window.setContentSize(CGSize(width: 460, height: 300))
    pane.layoutSubtreeIfNeeded()
    _ = try Rendering.bitmap(of: pane)
    #expect(pane.documentView.visibleRect.origin == origin)
  }

  @Test func revealingAFarRowLaysOutOnlyItsOwnParagraph() throws {
    let pane = PaneView()
    let rows = 100_000
    pane.content = CodeRows.content(
      count: rows, length: 300, blocks: [PaneBlock(rows: 98_765..<98_766, style: .tinted(.a))])
    let provider = FixedHighlights(
      [
        0: [
          CodeRows.start(ofRow: 98_765, length: 300) + 250..<CodeRows.start(
            ofRow: 98_765, length: 300) + 255
        ]
      ])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 400))
    defer { window.close() }
    let clock = ContinuousClock()
    let duration = clock.measure { pane.reveal(block: 0) }
    #expect(duration < .milliseconds(100), "\(duration)")
    #expect(pane.documentView.visibleRect.minX > 0)
  }

  /// The row of the changed block.
  private static let blockRow: CGFloat = 600

  /// The length of every line.
  private static let length = 300

  private static let textInset: CGFloat = 12

  /// A pane of 1 000 long rows whose block at row 600 changes the text from `changeAtColumn`.
  private static func pane(changeAtColumn column: Int) -> (PaneView, NSWindow, FixedHighlights) {
    let row = Int(blockRow)
    let pane = PaneView()
    pane.content = CodeRows.content(
      count: 1_000, length: length,
      blocks: [PaneBlock(rows: row..<row + 2, style: .tinted(.b), marker: .changed)])
    let start = CodeRows.start(ofRow: row, length: length)
    let provider = FixedHighlights([0: [start + column..<start + column + 5]])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 300))
    return (pane, window, provider)
  }

  private static func characterWidth(_ theme: Theme) -> CGFloat {
    ("0" as NSString).size(withAttributes: [.font: theme.font]).width
  }
}

/// Highlights given in advance for each block.
@MainActor
final class FixedHighlights: PaneHighlightProvider {
  private let runs: [Int: [Range<Int>]]

  init(_ runs: [Int: [Range<Int>]]) {
    self.runs = runs
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    runs[block] ?? []
  }
}
