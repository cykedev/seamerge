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

  @Test func blocksInWhichThePanesDoNotDifferGetNoBand() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    let all = layout.seam.bands.map(\.block)
    try #require(all.count > 2)
    layout.seam.blocksWithoutBand = [all[1]]
    #expect(layout.seam.bands.map(\.block) == all.filter { $0 != all[1] })
  }

  @Test func edgeOfAFewRowsKeepsItsControlPointsHalfWayAcross() {
    let width = Theme.seamWidth
    for rise in [0, 10, 2 * width, -2 * width] {
      let controls = PaneSeam.controlPoints(
        from: CGPoint(x: 0, y: 100), to: CGPoint(x: width, y: 100 + rise))
      #expect(controls.first == CGPoint(x: width / 2, y: 100), "rise \(rise)")
      #expect(controls.second == CGPoint(x: width / 2, y: 100 + rise), "rise \(rise)")
    }
  }

  @Test(arguments: [false, true], [-600.0, -120, 120, 600])
  func steepEdgeBendsOverMoreOfTheSeamAndStaysWithinIt(leftToRight: Bool, rise: Double) {
    let width = Theme.seamWidth
    let (left, right) = (CGFloat(10), 10 + width)
    let start = CGPoint(x: leftToRight ? left : right, y: 300)
    let end = CGPoint(x: leftToRight ? right : left, y: 300 + rise)
    let (first, second) = PaneSeam.controlPoints(from: start, to: end)
    // The control points move beyond half way, so that the curve turns less sharply at the
    // ends, and stay level with them.
    #expect(abs(first.x - start.x) > width / 2 && abs(second.x - end.x) > width / 2)
    #expect(first.y == start.y && second.y == end.y)
    // Along the curve, every point lies within the seam and between the heights of its ends,
    // and the height only ever moves towards the end: no point of a wedge is overshot.
    var previous = start.y
    for step in 0...200 {
      let t = CGFloat(step) / 200
      let u = 1 - t
      let a = u * u * u
      let b = 3 * u * u * t
      let c = 3 * u * t * t
      let d = t * t * t
      let x = a * start.x + b * first.x + c * second.x + d * end.x
      let y = a * start.y + b * first.y + c * second.y + d * end.y
      #expect(x >= left - 1e-9 && x <= right + 1e-9, "x \(x) at \(t)")
      #expect(y >= min(start.y, end.y) - 1e-9 && y <= max(start.y, end.y) + 1e-9, "y \(y)")
      #expect(rise > 0 ? y >= previous - 1e-9 : y <= previous + 1e-9, "y \(y) at \(t)")
      previous = y
    }
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
    #expect(painting.shadings[0].edges.top != nil)
    #expect(painting.shadings[0].edges.bottom == nil)

    var unmarked = pane.content
    unmarked.marksBlocksWithoutRows = false
    pane.content = unmarked
    let plain = pane.textView.painting(forRows: rows.lowerBound..<rows.lowerBound + 1)
    #expect(
      plain.shadings[0].edges.top == nil, "a result pane draws nothing for a block without rows")
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
    #expect(painting.shadings[0].edges.top == nil)
    #expect(painting.shadings[0].edges.bottom != nil)
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

  @Test(arguments: [false, true])
  func panesFollowTheTrackSteadilyWhileOneIsScrolledByHand(scrollsTheRight: Bool) throws {
    let (layout, window) = ConnectedLayout.hosted(height: 320)
    defer { window.close() }
    let leader = scrollsTheRight ? layout.right : layout.left
    let rowHeight = leader.rowHeight
    let step = rowHeight / 3
    // From a place where the panes stand together on the track; at the very top, the reading
    // lines of panes that start alike lie apart on it.
    leader.placeReadingLine(at: leader.readingLinePlace + 10 * rowHeight, x: 0)
    for direction in [1.0, -1.0] {
      var places = [layout.left.readingLinePlace, layout.right.readingLinePlace]
      var leaderStoodStill = false
      var steps = 0
      leader.textView.liveScrollDidStart()
      while steps < 2_000 {
        let origin = leader.documentView.visibleRect.origin
        leader.documentView.scroll(CGPoint(x: 0, y: origin.y + direction * step))
        let now = [layout.left.readingLinePlace, layout.right.readingLinePlace]
        let moves = zip(now, places).map { ($0 - $1) * direction }
        for (index, move) in moves.enumerated() {
          #expect(move >= -0.001, "pane \(index) turns back at step \(steps)")
          #expect(move <= rowHeight, "pane \(index) jumps \(move) at step \(steps)")
        }
        let leaderMove = scrollsTheRight ? moves[1] : moves[0]
        let otherMove = scrollsTheRight ? moves[0] : moves[1]
        if leaderMove < 0.001 && otherMove > 0.001 {
          leaderStoodStill = true
        }
        guard moves.contains(where: { $0 > 0.001 }) else { break }
        places = now
        steps += 1
      }
      leader.textView.liveScrollDidEnd()
      #expect(steps > 100, "the panes went a long way, \(direction)")
      #expect(leaderStoodStill, "the pane stood still across a block without its rows")
    }
  }

  @Test func trackTakesEveryPlaceSteadilyToEachPaneAndBack() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    let track = try #require(ScrollTrack(panes: [layout.left, layout.right]))
    let end = max(
      layout.left.verticalSpan(ofRows: 0..<layout.left.content.lineNumbers.count).upperBound,
      layout.right.verticalSpan(ofRows: 0..<layout.right.content.lineNumbers.count).upperBound)
    let step: CGFloat = 1
    var previous = [
      track.place(ofPane: 0, atTrackPosition: 0), track.place(ofPane: 1, atTrackPosition: 0),
    ]
    var position: CGFloat = step
    var standing = [0, 0]
    while position < 2 * end {
      for pane in 0..<2 {
        let place = track.place(ofPane: pane, atTrackPosition: position)
        #expect(place >= previous[pane] && place - previous[pane] <= step + 0.001)
        if place == previous[pane] {
          standing[pane] += 1
        }
        #expect(track.trackPositions(ofPane: pane, atPlace: place).contains(position))
        previous[pane] = place
      }
      position += step
    }
    #expect(standing[0] > 0 && standing[1] > 0, "each pane stands still across a block")
  }

  @Test func panesWithDifferentBlocksStayWhereTheyAreUntilTheyShowTheSameAgain() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    layout.right.documentView.scroll(CGPoint(x: 0, y: 400))
    let leftOrigin = layout.left.documentView.visibleRect.origin
    // The left pane gets a text of other blocks first, as a window does that shows other files.
    layout.left.content = CodeRows.content(
      count: 30, blocks: [PaneBlock(rows: 2..<4, style: .tinted(.a))])
    #expect(ScrollTrack(panes: [layout.left, layout.right]) == nil)
    let right = layout.right.documentView.visibleRect.origin
    layout.right.documentView.scroll(CGPoint(x: 0, y: right.y + 40))
    #expect(layout.left.documentView.visibleRect.origin.y <= leftOrigin.y)
    var content = CodeRows.content(count: 30, blocks: [PaneBlock(rows: 2..<2, style: .tinted(.b))])
    content.marksBlocksWithoutRows = true
    layout.right.content = content
    layout.right.documentView.scroll(CGPoint(x: 0, y: 0))
    let track = try #require(ScrollTrack(panes: [layout.left, layout.right]))
    // Together on the track again: the left pane stands its two rows further down, where the
    // track puts it, at the nearest whole pixel, to which a pane scrolls.
    let rightPositions = track.trackPositions(ofPane: 1, atPlace: layout.right.readingLinePlace)
    let place = track.place(ofPane: 0, atTrackPosition: rightPositions.lowerBound)
    let origin = place - Theme.readingLine * layout.left.visibleHeight
    let scale = window.backingScaleFactor
    #expect(layout.left.scrollOrigin.y == (origin * scale).rounded() / scale)
  }

  @Test func paneThatScrollsToAPlaceTakesTheOthersAlongToItsPlaceOnTheTrack() throws {
    let (layout, window) = ConnectedLayout.hosted()
    defer { window.close() }
    // The left pane brings the middle of a removal to its reading line.
    let block = ConnectedLayout.removal + 3
    let span = layout.left.verticalSpan(ofRows: layout.left.content.blocks[block].rows)
    layout.left.placeReadingLine(at: (span.lowerBound + span.upperBound) / 2, x: 0)
    let hairline = layout.right.verticalSpan(ofRows: layout.right.content.blocks[block].rows)
    #expect(layout.right.content.blocks[block].rows.isEmpty)
    #expect(abs(layout.right.readingLinePlace - hairline.lowerBound) < 0.001)
  }
}

/// Two panes side by side that show the lines of their files without filler rows, connected by
/// a seam and scrolling over a common track, without a window around them.
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
    sync.setTrack(for: [left, right])
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

  /// The layout in a window of `height`, laid out, drawn in `appearance`.
  static func hosted(
    height: CGFloat = 500, appearance: NSAppearance? = NSAppearance(named: .aqua)
  ) -> (ConnectedLayout, NSWindow) {
    let layout = ConnectedLayout()
    let window = Rendering.host(
      layout, size: CGSize(width: 1000, height: height), appearance: appearance)
    return (layout, window)
  }
}
