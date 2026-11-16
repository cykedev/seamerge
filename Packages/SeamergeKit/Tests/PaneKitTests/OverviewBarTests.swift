import AppKit
import Testing

@testable import PaneKit

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
    let ground = try Rendering.color(
      in: bitmap, at: CGPoint(x: bar.frame.minX + 4, y: slot.maxY - 2))
    let mark = Contrast.over(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.a)), in: appearance), ground)
    try expect(in: bitmap, at: CGPoint(x: bar.frame.minX + 4, y: y), is: mark)
    // The frame of the visible part is tall enough to grab, however long the text.
    #expect(bar.rect(for: .knob).height >= 20)

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

  @Test func marksOfATextThatFitsStandBesideTheirRowsWithoutAKnob() throws {
    let theme = Theme()
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(
      count: 10, length: 20, blocks: [PaneBlock(rows: 3..<4, style: .tinted(.a))])
    let bar = OverviewBar()
    bar.theme = theme
    bar.marks = [
      OverviewMark(
        rows: 3..<4, style: .tinted(.a), placement: .leading, block: 0,
        accessibilityLabel: "Changed in A, line 4")
    ]
    pane.overviewBar = bar
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 600), appearance: appearance)
    defer { window.close() }
    #expect(!bar.isEnabled)
    let bitmap = try Rendering.bitmap(of: pane)
    let x = bar.frame.minX + 4
    let ground = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: 500))
    let mark = Contrast.over(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.a)), in: appearance), ground)
    let row = 3.5 * theme.rowHeight
    try expect(in: bitmap, at: CGPoint(x: x, y: row), is: mark)
    // Stretched over the whole bar, the mark would stand at a third of its height instead.
    try expect(in: bitmap, at: CGPoint(x: x, y: 0.35 * 600), is: ground)
  }

  @Test func marksOfALieLeftMarksOfBRightAndConflictsAcrossTheBar() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let left = bar.frame.minX + 3
    let right = bar.frame.maxX - 3
    let ground = try Rendering.color(in: bitmap, at: CGPoint(x: right, y: Self.y(of: 290, in: bar)))
    let color = { (style: BlockStyle) in
      Contrast.over(
        Contrast.resolve(theme.overviewMarkColor(for: style), in: self.appearance), ground)
    }
    let (a, b, conflict) = (color(.tinted(.a)), color(.tinted(.b)), color(.tinted(.conflict)))
    // Only an open conflict keeps the full symbol value; the other marks are toned down.
    #expect(
      Self.isClose(
        conflict,
        try #require(Contrast.resolve(theme.symbolColor(for: .conflict), in: appearance))))
    #expect(
      !Self.isClose(a, try #require(Contrast.resolve(theme.symbolColor(for: .a), in: appearance))))
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

  @Test func pointerMovesWithTheMarksOfTheCurrentBlock() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    pane.documentView.scroll(CGPoint(x: 0, y: pane.documentView.frame.height))
    bar.currentBlock = 1
    let label = try #require(Contrast.resolve(.labelColor, in: appearance))
    func pointer(atRow row: Int) -> CGPoint {
      CGPoint(x: bar.frame.minX + 1, y: Self.y(of: row, in: bar))
    }
    let before = try Rendering.bitmap(of: pane)
    let ground = try Rendering.color(in: before, at: pointer(atRow: 70))
    try expect(in: before, at: pointer(atRow: 170), is: Contrast.over(label, ground))
    bar.marks[1].rows = 60..<80
    let after = try Rendering.bitmap(of: pane)
    try expect(in: after, at: pointer(atRow: 70), is: Contrast.over(label, ground))
    #expect(try Rendering.color(in: after, at: pointer(atRow: 170)) == ground)
  }

  @Test func frameOfTheVisiblePartSpansTheBarAndGetsStrongerUnderThePointer() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    let knob = bar.convert(bar.rect(for: .knob), to: pane)
    let ground = try Rendering.color(
      in: Rendering.bitmap(of: pane), at: CGPoint(x: bar.frame.midX, y: Self.y(of: 290, in: bar)))
    let resolve = { (color: NSColor) in Contrast.resolve(color, in: self.appearance) }
    // The outline runs down both sides of the bar, outside the marks; on the leading side it
    // lies over the fill of the frame.
    let leading = CGPoint(x: bar.frame.minX + 1, y: knob.midY)
    let trailing = CGPoint(x: bar.frame.maxX - 0.5, y: knob.midY)
    func expectOutline(emphasized: Bool, sourceLocation: SourceLocation = #_sourceLocation) throws {
      let bitmap = try Rendering.bitmap(of: pane)
      let outline = resolve(theme.visibleRegionOutline(emphasized: emphasized))
      let fill = Contrast.over(resolve(theme.visibleRegionFill(emphasized: emphasized)), ground)
      try expect(
        in: bitmap, at: leading, is: Contrast.over(outline, fill), sourceLocation: sourceLocation)
      try expect(
        in: bitmap, at: trailing, is: Contrast.over(outline, ground),
        sourceLocation: sourceLocation)
    }
    try expectOutline(emphasized: false)
    #expect(knob.height >= 20)

    let entered = try #require(
      NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
        userData: nil))
    bar.mouseEntered(with: entered)
    try expectOutline(emphasized: true)
    bar.mouseExited(with: entered)
    try expectOutline(emphasized: false)
  }

  @Test func scrollingDrawsOnlyTheStripeOfTheFrameAgain() throws {
    let (pane, bar, window) = Self.paneWithBar(theme: Theme(), appearance: appearance)
    defer { window.close() }
    let before = bar.rect(for: .knob)
    let invalid = Invalidations.recording {
      pane.documentView.scroll(CGPoint(x: 0, y: 3 * pane.theme.rowHeight))
    }
    let after = bar.rect(for: .knob)
    #expect(after.minY > before.minY)
    let union = invalid.reduce(CGRect.null) { $0.union($1) }
    // The stripe of the frame, where it was and where it is, across the whole width of the bar,
    // and nothing far from it.
    let stripes = CGRect(
      x: 0, y: before.minY, width: bar.bounds.width, height: after.maxY - before.minY)
    #expect(union.contains(stripes), "\(invalid)")
    #expect(union.minY >= before.minY - 2 && union.maxY <= after.maxY + 2, "\(invalid)")
  }

  /// The tracking loop of the scroller cannot run in the test process, as it lets other tests
  /// run on the main queue; the test takes up where the loop ends, at the release.
  @Test func frameIsQuietAgainAfterADragThatEndsOutsideTheBar() throws {
    let theme = Theme()
    let (pane, bar, window) = Self.paneWithBar(theme: theme, appearance: appearance)
    defer { window.close() }
    let resolve = { (color: NSColor) in Contrast.resolve(color, in: self.appearance) }
    let knob = bar.convert(bar.rect(for: .knob), to: pane)
    let trailing = CGPoint(x: bar.frame.maxX - 0.5, y: knob.midY)
    let ground = try Rendering.color(
      in: Rendering.bitmap(of: pane), at: CGPoint(x: bar.frame.midX, y: Self.y(of: 290, in: bar)))
    func outline(emphasized: Bool) -> NSColor {
      Contrast.over(resolve(theme.visibleRegionOutline(emphasized: emphasized)), ground)
    }
    let entered = try #require(
      NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
        userData: nil))
    bar.mouseEntered(with: entered)

    // Released over the bar: still under the pointer.
    bar.endTracking(releasedAt: bar.convert(CGPoint(x: bar.bounds.midX, y: 40), to: nil))
    try expect(in: try Rendering.bitmap(of: pane), at: trailing, is: outline(emphasized: true))

    // Released over the text: quiet again, though no exit came.
    bar.endTracking(releasedAt: pane.convert(CGPoint(x: 20, y: 40), to: nil))
    try expect(in: try Rendering.bitmap(of: pane), at: trailing, is: outline(emphasized: false))
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

/// Records the parts of overview bars that are marked to be drawn again.
///
/// AppKit offers no way to read the part of a view that waits to be drawn, so the method that
/// marks it is extended for overview bars, once for the test process: it notes the part, then
/// does what the scroller does.
@MainActor
private enum Invalidations {
  private static var rects: [CGRect]?
  private static var isInstalled = false

  /// The parts of overview bars marked while `body` runs, as a whole bar or as rectangles.
  static func recording(_ body: () -> Void) -> [CGRect] {
    install()
    rects = []
    body()
    defer { rects = nil }
    return rects ?? []
  }

  private static func install() {
    guard !isInstalled else { return }
    isInstalled = true
    let selector = #selector(NSView.setNeedsDisplay(_:))
    guard let inherited = class_getInstanceMethod(NSScroller.self, selector) else { return }
    typealias Mark = @convention(c) (AnyObject, Selector, CGRect) -> Void
    let mark = unsafeBitCast(method_getImplementation(inherited), to: Mark.self)
    let noting: @convention(block) (AnyObject, CGRect) -> Void = { bar, rect in
      MainActor.assumeIsolated { rects?.append(rect) }
      mark(bar, selector, rect)
    }
    class_addMethod(
      OverviewBar.self, selector, imp_implementationWithBlock(noting),
      method_getTypeEncoding(inherited))
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
