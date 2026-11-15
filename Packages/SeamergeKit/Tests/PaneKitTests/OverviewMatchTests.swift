import AppKit
import Testing

@testable import PaneKit

/// Checks the strokes that the overview bar draws for the matches of a search: where they lie,
/// how they merge, and that they lie above the marks of the blocks.
@MainActor
@Suite struct OverviewMatchTests {
  private let area = CGRect(x: 2, y: 3, width: 8, height: 500)

  @Test func strokeLiesAcrossTheMiddleOfItsRow() throws {
    let layout = OverviewLayout(
      marks: [], matchRows: [54_321], rowCount: 100_000, rowHeight: 20, area: area)
    try #require(layout.matchSpans.count == 1)
    let span = layout.matchSpans[0]
    #expect(span.upperBound - span.lowerBound == Theme.overviewMatchHeight)
    let middle = area.minY + 54_321.5 / 100_000 * area.height
    #expect(abs((span.lowerBound + span.upperBound) / 2 - middle) < 0.01)
  }

  @Test func strokesThatTouchMergeAndOthersStayApart() {
    // Half a point per row: the strokes of neighboring rows overlap.
    let layout = OverviewLayout(
      marks: [], matchRows: [10, 11, 12, 500], rowCount: 1_000, rowHeight: 20, area: area)
    #expect(layout.matchSpans.count == 2)
    #expect(layout.matchSpans[0].lowerBound == area.minY + 10.5 * 0.5 - 1)
    #expect(layout.matchSpans[0].upperBound == area.minY + 12.5 * 0.5 + 1)
    #expect(layout.matchSpans[1].lowerBound == area.minY + 500.5 * 0.5 - 1)
  }

  @Test func strokesOfATextThatFitsStandBesideTheirRows() {
    let layout = OverviewLayout(
      marks: [], matchRows: [3], rowCount: 10, rowHeight: 20, area: area)
    #expect(layout.matchSpans == [area.minY + 69..<area.minY + 71])
  }

  @Test func strokesStayWithinTheBarAtItsEnds() {
    let layout = OverviewLayout(
      marks: [], matchRows: [0, 99_999], rowCount: 100_000, rowHeight: 20, area: area)
    #expect(layout.matchSpans.first?.lowerBound == area.minY)
    #expect(layout.matchSpans.last?.upperBound == area.maxY)
  }

  @Test func strokeIsDrawnAcrossTheBarAboveTheMarkOfItsBlockOnASeam() throws {
    let theme = Theme()
    let appearance = Look.all[0].appearance
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(
      count: 100, length: 30, blocks: [PaneBlock(rows: 40..<60, style: .tinted(.a))])
    let bar = OverviewBar()
    bar.marks = [
      OverviewMark(
        rows: 40..<60, style: .tinted(.a), placement: .fullWidth, block: 0,
        accessibilityLabel: "Changed in A")
    ]
    bar.matchRows = [50]
    pane.overviewBar = bar
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 600), appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let resolve = { (color: NSColor) in try #require(Contrast.resolve(color, in: appearance)) }
    let ground = try Rendering.color(in: bitmap, at: CGPoint(x: bar.frame.maxX - 1, y: 590))
    let mark = Contrast.over(try resolve(theme.overviewMarkColor(for: .tinted(.a))), ground)
    let stroke = Contrast.over(try resolve(theme.overviewMatchColor), ground)
    // The text is taller than the bar, so its rows share the height of the track.
    let slot = bar.rect(for: .knobSlot)
    let y = bar.frame.minY + slot.minY + 50.5 / 100 * slot.height
    for x in [bar.frame.minX + 1, bar.frame.midX, bar.frame.maxX - 1] {
      #expect(Self.isClose(try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y)), stroke))
    }
    // The seam of the bar's tone, then the mark.
    let seam = try Rendering.color(in: bitmap, at: CGPoint(x: bar.frame.midX, y: y + 1.5))
    #expect(Self.isClose(seam, ground))
    let below = try Rendering.color(in: bitmap, at: CGPoint(x: bar.frame.midX, y: y + 4))
    #expect(Self.isClose(below, mark))
  }

  private static func isClose(_ first: NSColor, _ second: NSColor) -> Bool {
    abs(first.redComponent - second.redComponent) < 0.02
      && abs(first.greenComponent - second.greenComponent) < 0.02
      && abs(first.blueComponent - second.blueComponent) < 0.02
  }
}
