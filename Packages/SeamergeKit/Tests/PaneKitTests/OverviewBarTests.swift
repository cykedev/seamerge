import AppKit
import PaneKit
import Testing

/// Checks what the overview bar shows beside a pane and how it scrolls the pane.
@MainActor
@Suite struct OverviewBarTests {
  private let appearance = Look.all[0].appearance

  @Test func singleChangedLineAmongOneHundredThousandRowsIsShownAndCanBePressed() throws {
    let theme = Theme()
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(
      count: 100_000, length: 40, blocks: [PaneBlock(rows: 54_321..<54_322, style: .tinted(.a))])
    let bar = OverviewBar()
    bar.marks = [
      OverviewMark(
        rows: 54_321..<54_322, style: .tinted(.a), placement: .leading, block: 0,
        accessibilityLabel: "Changed in A, line 54 322")
    ]
    pane.overviewBar = bar
    let recorder = BarRecorder()
    bar.delegate = recorder
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 600), appearance: appearance)
    defer { window.close() }
    let slot = bar.rect(for: .knobSlot)
    let y = slot.minY + 54_321.5 / 100_000 * slot.height
    let bitmap = try Rendering.bitmap(of: pane)
    let mark = try #require(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.a)), in: appearance))
    try expect(in: bitmap, at: CGPoint(x: bar.frame.minX + 4, y: y), is: mark)

    let elements = try #require(bar.accessibilityChildren() as? [NSAccessibilityElement])
    try #require(elements.count == 1)
    #expect(elements[0].accessibilityLabel() == "Changed in A, line 54 322")
    #expect(elements[0].accessibilityRole() == .button)
    #expect(elements[0].accessibilityPerformPress())
    #expect(recorder.blocks == [0])
    let visibleRows =
      pane.documentView.visibleRect.minY / theme.rowHeight..<pane.documentView.visibleRect.maxY
      / theme.rowHeight
    #expect(visibleRows.contains(54_321.5))
  }

  @Test func marksOfALieLeftMarksOfBRightAndConflictsAcrossTheBar() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let left = bar.frame.minX + 3
    let right = bar.frame.maxX - 3
    let a = try #require(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.a)), in: appearance))
    let b = try #require(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.b)), in: appearance))
    let conflict = try #require(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.conflict)), in: appearance))
    let ground = try Rendering.color(in: bitmap, at: CGPoint(x: right, y: Self.y(of: 290, in: bar)))
    try expect(in: bitmap, at: CGPoint(x: left, y: Self.y(of: 130, in: bar)), is: a)
    try expect(in: bitmap, at: CGPoint(x: right, y: Self.y(of: 130, in: bar)), is: ground)
    try expect(in: bitmap, at: CGPoint(x: left, y: Self.y(of: 170, in: bar)), is: ground)
    try expect(in: bitmap, at: CGPoint(x: right, y: Self.y(of: 170, in: bar)), is: b)
    try expect(in: bitmap, at: CGPoint(x: left, y: Self.y(of: 230, in: bar)), is: conflict)
    try expect(in: bitmap, at: CGPoint(x: right, y: Self.y(of: 230, in: bar)), is: conflict)
  }

  @Test func visibleAreaFollowsTheTextAndTheCurrentBlockIsPointedAt() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    let middle = bar.frame.midX
    var bitmap = try Rendering.bitmap(of: pane)
    let insideTop = try Rendering.color(
      in: bitmap, at: CGPoint(x: middle, y: Self.y(of: 2, in: bar)))
    let outside = try Rendering.color(
      in: bitmap, at: CGPoint(x: middle, y: Self.y(of: 280, in: bar)))
    #expect(insideTop != outside, "the visible area is lighter or darker than the rest")
    pane.documentView.scroll(CGPoint(x: 0, y: pane.documentView.frame.height))
    bitmap = try Rendering.bitmap(of: pane)
    #expect(
      try Rendering.color(in: bitmap, at: CGPoint(x: middle, y: Self.y(of: 2, in: bar))) == outside)

    let pointer = CGPoint(x: bar.frame.minX + 1, y: Self.y(of: 170, in: bar))
    #expect(try Rendering.color(in: Rendering.bitmap(of: pane), at: pointer) == outside)
    bar.currentBlock = 1
    let label = try #require(Contrast.resolve(.labelColor, in: appearance))
    try expect(in: try Rendering.bitmap(of: pane), at: pointer, is: Contrast.over(label, outside))
  }

  @Test func openConflictHasANotchWhenColorsAreNotToBeRelyOn() throws {
    for differentiates in [false, true] {
      let theme = Theme(differentiatesWithoutColor: differentiates)
      let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
      defer { window.close() }
      let conflict = try #require(
        Contrast.resolve(theme.overviewMarkColor(for: .tinted(.conflict)), in: appearance))
      let edge = CGPoint(x: bar.frame.minX + 2.5, y: Self.y(of: 230, in: bar))
      let color = try Rendering.color(in: Rendering.bitmap(of: pane), at: edge)
      #expect(Self.isClose(color, conflict) != differentiates, "differentiates \(differentiates)")
    }
  }

  @Test func barIsNamedForVoiceOver() {
    let bar = OverviewBar()
    #expect(bar.accessibilityLabel() == "Overview")
  }

  /// A pane of 300 rows with a change of A at rows 120 to 140, of B at 160 to 180, and an open
  /// conflict at 220 to 240.
  private static func paneWithBar(
    theme: Theme, appearance: NSAppearance
  ) -> (PaneView, OverviewBar, NSWindow) {
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(count: 300)
    let bar = OverviewBar()
    bar.theme = theme
    func mark(
      _ rows: Range<Int>, _ style: BlockStyle, _ placement: OverviewMark.Placement, _ block: Int
    )
      -> OverviewMark
    {
      OverviewMark(
        rows: rows, style: style, placement: placement, block: block, accessibilityLabel: "")
    }
    bar.marks = [
      mark(120..<140, .tinted(.a), .leading, 0), mark(160..<180, .tinted(.b), .trailing, 1),
      mark(220..<240, .tinted(.conflict), .fullWidth, 2),
    ]
    pane.overviewBar = bar
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 300), appearance: appearance)
    return (pane, bar, window)
  }

  /// The height in the bar, in the pane's coordinates, of the middle of `row` among 300.
  private static func y(of row: Int, in bar: OverviewBar) -> CGFloat {
    let slot = bar.rect(for: .knobSlot)
    return bar.frame.minY + slot.minY + (CGFloat(row) + 0.5) / 300 * slot.height
  }

  private static func isClose(_ first: NSColor, _ second: NSColor) -> Bool {
    abs(first.redComponent - second.redComponent) < 0.02
      && abs(first.greenComponent - second.greenComponent) < 0.02
      && abs(first.blueComponent - second.blueComponent) < 0.02
  }

  private func expect(
    in bitmap: NSBitmapImageRep, at point: CGPoint, is expected: NSColor,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let color = try Rendering.color(in: bitmap, at: point)
    #expect(Self.isClose(color, expected), "\(color) at \(point)", sourceLocation: sourceLocation)
  }
}

/// Records the blocks that an overview bar reports.
@MainActor
private final class BarRecorder: OverviewBarDelegate {
  var blocks: [Int] = []

  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int) {
    blocks.append(block)
  }
}
