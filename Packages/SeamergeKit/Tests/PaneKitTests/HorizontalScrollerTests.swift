import AppKit
import Testing

@testable import PaneKit

/// Checks the scroller below a pane whose lines are wider than the pane: in either style that the
/// system gives scrollers, it lies wholly in the pane, its knob fits the width of the text, and a
/// legacy scroller takes its height from the text, the gutter and the decision column, which end
/// with the text above it, while an overlay scroller lies above them all.
@MainActor
@Suite struct HorizontalScrollerTests {
  private static let size = CGSize(width: 400, height: 300)

  /// A pane of `lineCount` lines, each `width` characters long, in a window at the size above.
  private static func hostedPane(lineCount: Int, width: Int) -> (PaneView, NSWindow) {
    let pane = PaneView()
    let lines = (0..<lineCount).map { "\($0) " + String(repeating: "x", count: width) }
    pane.content = PaneContent(
      text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map { Int32($0) })
    return (pane, Rendering.host(pane, size: size))
  }

  private static func scrollView(of pane: PaneView) throws -> PaneScrollView {
    try #require(pane.subviews.lazy.compactMap { $0 as? PaneScrollView }.first)
  }

  @Test(arguments: [NSScroller.Style.overlay, .legacy])
  func scrollerLiesWhollyInThePaneAndLeavesTheTextTheRightHeight(style: NSScroller.Style) throws {
    // Few lines, so that the text is as high as the part of the pane it is visible in.
    let (pane, window) = Self.hostedPane(lineCount: 5, width: 200)
    defer { window.close() }
    let scrollView = try Self.scrollView(of: pane)
    // The system sets the style after the pane has laid out, as it does shortly after the app
    // starts.
    scrollView.scrollerStyle = style == .overlay ? .legacy : .overlay
    pane.layoutSubtreeIfNeeded()
    scrollView.scrollerStyle = style
    pane.layoutSubtreeIfNeeded()
    let scroller = try #require(scrollView.horizontalScroller)
    #expect(scrollView.hasHorizontalScroller)
    #expect(!scroller.isHidden)
    #expect(
      scroller.frame
        == CGRect(
          x: 0, y: scrollView.bounds.maxY - scroller.frame.height, width: scrollView.bounds.width,
          height: scroller.frame.height))
    #expect(scroller.frame.height > 0)
    let expectedHeight =
      style == .overlay ? scrollView.bounds.height : scroller.frame.minY
    #expect(pane.clipView.frame.height == expectedHeight)
    #expect(pane.documentView.frame.height == expectedHeight)
  }

  @Test(arguments: [NSScroller.Style.overlay, .legacy])
  func gutterAndDecisionColumnEndWithTheVisibleText(style: NSScroller.Style) throws {
    let (pane, window) = Self.hostedPane(lineCount: 50, width: 200)
    defer { window.close() }
    pane.decisionColumn = DecisionColumnView()
    let scrollView = try Self.scrollView(of: pane)
    scrollView.scrollerStyle = style
    pane.layoutSubtreeIfNeeded()
    let column = try #require(pane.decisionColumn)
    let scroller = try #require(scrollView.horizontalScroller)
    let textBottom = pane.convert(pane.clipView.frame, from: scrollView).maxY
    // The legacy scroller takes the bottom of the pane below the text with its track; the
    // overlay scroller lies over the text, which reaches the bottom.
    let scrollerTop = pane.convert(scroller.frame, from: scrollView).minY
    #expect(textBottom == (style == .legacy ? scrollerTop : pane.bounds.maxY))
    #expect(textBottom < pane.bounds.maxY || style == .overlay)
    #expect(pane.gutterView.frame.maxY == textBottom)
    #expect(column.frame.maxY == textBottom)
    #expect(pane.gutterView.frame.minY == 0 && column.frame.minY == 0)
  }

  @Test func lastLineScrollsWhollyAboveALegacyScroller() throws {
    let (pane, window) = Self.hostedPane(lineCount: 100, width: 200)
    defer { window.close() }
    let scrollView = try Self.scrollView(of: pane)
    scrollView.scrollerStyle = .legacy
    pane.layoutSubtreeIfNeeded()
    pane.scroll(to: CGPoint(x: 0, y: pane.verticalScrollRange))
    let scroller = try #require(scrollView.horizontalScroller)
    let lastRowBottom = CGFloat(pane.displayRows.lineCount) * pane.rowHeight
    let scrollerTop = scroller.frame.minY - pane.clipView.frame.minY + pane.scrollOrigin.y
    #expect(lastRowBottom <= scrollerTop)
  }

  @Test func knobFitsTheWidthOfTheTextAfterTheFirstLayout() throws {
    let (pane, window) = Self.hostedPane(lineCount: 50, width: 300)
    defer { window.close() }
    let scrollView = try Self.scrollView(of: pane)
    let scroller = try #require(scrollView.horizontalScroller)
    let proportion = pane.clipView.bounds.width / pane.documentView.frame.width
    #expect(proportion > 0.05 && proportion < 0.5)
    #expect(abs(scroller.knobProportion - proportion) < 0.001)
    #expect(scroller.doubleValue == 0)
    let knob = scroller.rect(for: .knob)
    let slot = scroller.rect(for: .knobSlot)
    #expect(knob.minX == slot.minX)
    #expect(abs(knob.width - slot.width * proportion) <= 1)
  }

  /// The scroller takes on a new style without its knob; the scroll view hands the knob over
  /// again, so that the scroller does not show the least knob at its end until the user scrolls.
  @Test(arguments: [NSScroller.Style.overlay, .legacy])
  func newStyleHandsTheScrollerItsKnobAgain(style: NSScroller.Style) throws {
    let (pane, window) = Self.hostedPane(lineCount: 50, width: 300)
    defer { window.close() }
    let scrollView = try Self.scrollView(of: pane)
    let scroller = RecordingScroller()
    scrollView.scrollerStyle = style == .overlay ? .legacy : .overlay
    scrollView.horizontalScroller = scroller
    pane.needsLayout = true
    pane.layoutSubtreeIfNeeded()
    pane.scroll(to: CGPoint(x: 120, y: 0))
    let proportion = scroller.knobProportion
    let value = scroller.doubleValue
    #expect(proportion > 0 && proportion < 1)
    #expect(value > 0 && value < 1)
    scroller.assignments = []
    scrollView.scrollerStyle = style
    try #require(scrollView.scrollerStyle == style)
    #expect(scroller.assignments.contains { $0.proportion != proportion })
    #expect(scroller.assignments.contains { $0.value != value })
    #expect(scroller.assignments.last?.proportion == proportion)
    #expect(scroller.assignments.last?.value == value)
  }
}

/// A scroller that records each size and place of its knob that it is given.
private final class RecordingScroller: NSScroller {
  var assignments: [(proportion: CGFloat, value: Double)] = []

  /// The scroll view would otherwise give a scroller of its own class the legacy style only.
  override class var isCompatibleWithOverlayScrollers: Bool { true }

  override var knobProportion: CGFloat {
    didSet { assignments.append((knobProportion, doubleValue)) }
  }

  override var doubleValue: Double {
    didSet { assignments.append((knobProportion, doubleValue)) }
  }
}
