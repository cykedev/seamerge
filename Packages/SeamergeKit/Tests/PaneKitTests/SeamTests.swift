import AppKit
import Testing

@testable import PaneKit

/// Checks the seam between two panes that connect their changes: its bands end where the
/// blocks end, to the pixel, also beyond the visible text; only the bands in view are drawn; the
/// seam lets clicks through and VoiceOver passes it by; blocks without rows show a hairline.
@MainActor
@Suite struct SeamTests {
  @Test func bandEndsLieOnTheHairlinesAtTheEdgesOfTheBlocks() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    let hairline = 1 / window.backingScaleFactor
    let bands = layout.seam.bands
    try #require(!bands.isEmpty)
    for band in bands {
      for (pane, end) in [(layout.left, band.left), (layout.right, band.right)] {
        let rows = pane.content.blocks[band.block].rows
        let span = pane.verticalSpan(ofRows: rows)
        let top = layout.seam.convert(CGPoint(x: 0, y: span.lowerBound), from: pane.documentView).y
        let bottom = layout.seam.convert(
          CGPoint(x: 0, y: span.upperBound), from: pane.documentView
        ).y
        if rows.isEmpty {
          #expect(end == top + hairline / 2...top + hairline / 2, "block \(band.block)")
        } else {
          #expect(end == top + hairline / 2...bottom - hairline / 2, "block \(band.block)")
        }
        // The boundary of a block lies on a pixel of the screen, as the edges of its rows do.
        #expect((top * window.backingScaleFactor).rounded() == top * window.backingScaleFactor)
      }
    }
  }

  @Test func bandOfABlockBeyondTheTopKeepsItsEndsWhereTheRowsAre() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    let block = 2
    let rows = layout.left.content.blocks[block].rows
    // The block starts above the visible text and ends within it.
    let y = layout.left.verticalSpan(ofRows: rows).lowerBound + layout.left.theme.rowHeight
    layout.sync.isEnabled = false
    layout.left.documentView.scroll(CGPoint(x: 0, y: y))
    layout.right.documentView.scroll(CGPoint(x: 0, y: y))
    let band = try #require(layout.seam.bands.first { $0.block == block })
    let textTop = layout.seam.convert(
      layout.left.documentView.visibleRect, from: layout.left.documentView
    ).minY
    #expect(band.left.lowerBound < textTop)
    let span = layout.left.verticalSpan(ofRows: rows)
    let top = layout.seam.convert(CGPoint(x: 0, y: span.lowerBound), from: layout.left.documentView)
      .y
    #expect(band.left.lowerBound == top + 1 / window.backingScaleFactor / 2)
  }

  @Test func onlyTheBandsInViewAreDrawn() throws {
    let (layout, window) = ConnectedLayout.hosted(height: 240)
    defer { window.close() }
    let blocks = layout.left.content.blocks.count
    let bands = layout.seam.bands.map(\.block)
    #expect(!bands.isEmpty)
    #expect(bands.count < blocks)
    #expect(bands == Array(bands[0]...bands[bands.count - 1]), "bands in view follow each other")
    layout.right.documentView.scroll(CGPoint(x: 0, y: layout.right.documentView.frame.height))
    #expect(layout.seam.bands.last?.block == blocks - 1)
  }

  @Test func seamLetsClicksThroughAndVoiceOverPassesItBy() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    #expect(layout.seam.hitTest(CGPoint(x: 4, y: 40)) == nil)
    #expect(!layout.seam.isAccessibilityElement())
    #expect(layout.seam.accessibilityChildren()?.isEmpty == true)
  }

  @Test func seamDrawsAgainWhenAPaneScrolls() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    layout.layoutSubtreeIfNeeded()
    layout.seam.needsDisplay = false
    layout.right.documentView.scroll(CGPoint(x: 0, y: 60))
    #expect(layout.seam.needsDisplay)
  }

  @Test func blockWithoutRowsDrawsAHairlineOnlyWhereBlocksWithoutRowsAreMarked() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    let pane = layout.right
    let rows = pane.content.blocks[ConnectedLayout.removal].rows
    try #require(rows.isEmpty)
    let painting = pane.textView.painting(forRows: rows.lowerBound..<rows.lowerBound + 1)
    #expect(painting.edges[0].top != nil)
    #expect(painting.edges[0].bottom == nil)

    var unmarked = pane.content
    unmarked.marksBlocksWithoutRows = false
    pane.content = unmarked
    let plain = pane.textView.painting(forRows: rows.lowerBound..<rows.lowerBound + 1)
    #expect(plain.edges[0].top == nil, "a result pane draws nothing for a block without rows")
  }

  @Test func blockWithoutRowsAtTheEndDrawsItsHairlineAtTheBottomOfTheLastRow() throws {
    let pane = PaneView()
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 300))
    defer { window.close() }
    var content = CodeRows.content(
      count: 3, blocks: [PaneBlock(rows: 3..<3, style: .tinted(.b))])
    content.marksBlocksWithoutRows = true
    pane.content = content
    let painting = pane.textView.painting(forRows: 2..<3)
    #expect(painting.edges[0].top == nil)
    #expect(painting.edges[0].bottom != nil)
  }

  @Test func marksOfABlockWithoutRowsStandOnItsHairline() throws {
    let pane = PaneView()
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 300))
    defer { window.close() }
    var content = CodeRows.content(
      count: 6, blocks: [PaneBlock(rows: 2..<2, style: .tinted(.b), marker: .removed)])
    content.marksBlocksWithoutRows = true
    pane.content = content
    pane.layoutSubtreeIfNeeded()
    let marks = pane.gutterView.boundaryMarks
    let mark = try #require(marks.first)
    #expect(marks.count == 1)
    #expect(mark.slot.midY == 2 * pane.theme.rowHeight)
    #expect(mark.boundary == 2)
    #expect(pane.gutterView.marks(ofRow: 2).isEmpty)
  }

  @Test func overviewGridKeepsTheMarksOnTheGridAndShowsTheVisiblePartConvertedToIt() throws {
    let (layout, window) = ConnectedLayout.hosted(height: 240)
    defer { window.close() }
    let bar = OverviewBar()
    layout.right.overviewBar = bar
    // The grid has twice the rows of the pane, each row of the pane at two rows of the grid.
    let rowCount = layout.right.content.lineNumbers.count
    layout.right.overviewGrid = OverviewGrid(
      rowCount: 2 * rowCount, collapsedRuns: [], gridRow: { 2 * $0 }, paneRow: { $0 / 2 })
    layout.layoutSubtreeIfNeeded()
    #expect(bar.displayRows.rowCount == 2 * rowCount)
    let visibleRows = Double(layout.right.documentView.visibleRect.height / layout.right.rowHeight)
    #expect(abs(bar.knobProportion - CGFloat(visibleRows / Double(rowCount))) < 0.001)

    bar.doubleValue = 1
    bar.sendAction(bar.action, to: bar.target)
    let visible = layout.right.documentView.visibleRect
    #expect(abs(visible.maxY - layout.right.documentView.frame.height) <= 1)
  }

  @Test func removedRowMappingLetsPanesTakeEachOthersOrigin() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    layout.sync.removeRowMapping(between: layout.left, and: layout.right)
    layout.left.documentView.scroll(CGPoint(x: 0, y: 120))
    #expect(layout.right.documentView.visibleRect.minY == 120)
  }
}

/// Two panes side by side that show the lines of their files without filler rows, connected by
/// a seam and coupled block by block, without a window around them.
///
/// Each block repeats a pattern of a removal, an insertion and a change, between unchanged rows.
@MainActor
final class ConnectedLayout: NSView {
  let left = PaneView()
  let right = PaneView()
  let seam: PaneSeam
  let sync = ScrollSync()

  /// The index of a block that the left side removed, which has no rows on the right.
  static let removal = 0

  init() {
    var leftBlocks: [PaneBlock] = []
    var rightBlocks: [PaneBlock] = []
    var leftRow = 0
    var rightRow = 0
    var leftStarts = [0]
    var rightStarts = [0]
    for _ in 0..<12 {
      // Unchanged, removal of 3, unchanged, insertion of 2, unchanged, change of 2 to 4.
      for (leftCount, rightCount, changed) in [
        (4, 4, false), (3, 0, true), (5, 5, false), (0, 2, true), (3, 3, false), (2, 4, true),
      ] {
        if changed {
          leftBlocks.append(
            PaneBlock(rows: leftRow..<leftRow + leftCount, style: .tinted(.a), marker: .removed))
          rightBlocks.append(
            PaneBlock(rows: rightRow..<rightRow + rightCount, style: .tinted(.b), marker: .added))
        }
        leftRow += leftCount
        rightRow += rightCount
        leftStarts.append(leftRow)
        rightStarts.append(rightRow)
      }
    }
    var leftContent = CodeRows.content(count: leftRow, blocks: leftBlocks)
    leftContent.marksBlocksWithoutRows = true
    var rightContent = CodeRows.content(count: rightRow, blocks: rightBlocks)
    rightContent.marksBlocksWithoutRows = true
    left.content = leftContent
    right.content = rightContent
    seam = PaneSeam(between: left, and: right)
    super.init(frame: .zero)
    for view in [left, seam, right] {
      addSubview(view)
    }
    sync.add(left)
    sync.add(right)
    sync.setRowMapping(
      between: left, and: right,
      forward: { Self.map($0, from: leftStarts, to: rightStarts) },
      backward: { Self.map($0, from: rightStarts, to: leftStarts) })
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let width = ((bounds.width - Theme.seamWidth) / 2).rounded(.down)
    left.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
    seam.frame = CGRect(x: width, y: 0, width: Theme.seamWidth, height: bounds.height)
    right.frame = CGRect(
      x: width + Theme.seamWidth, y: 0, width: bounds.width - width - Theme.seamWidth,
      height: bounds.height)
  }

  /// The layout in a window of `height`, laid out.
  static func hosted(height: CGFloat = 500) -> (ConnectedLayout, NSWindow) {
    let layout = ConnectedLayout()
    let window = Rendering.host(layout, size: CGSize(width: 1000, height: height))
    return (layout, window)
  }

  /// Maps `position` block by block from the starts `source` to the starts `target`, the last
  /// block that starts at or before it taking it.
  private static func map(_ position: Double, from source: [Int], to target: [Int]) -> Double {
    guard let index = source.indices.dropLast().last(where: { Double(source[$0]) <= position }),
      source[index + 1] > source[index]
    else {
      return position
    }
    let fraction = (position - Double(source[index])) / Double(source[index + 1] - source[index])
    return Double(target[index]) + fraction * Double(target[index + 1] - target[index])
  }
}
