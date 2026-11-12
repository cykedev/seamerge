import AppKit
import Testing

@testable import PaneKit

/// Checks the sign in the gutter that collapses a run of unchanged rows again once the user
/// expanded it: where it shows, what a click on it asks for, and what VoiceOver finds.
@MainActor
@Suite struct CollapsingAgainTests {
  @Test func pointerOverAnExpandedRunShowsItsSignBesideItsFirstRow() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let rowHeight = pane.theme.rowHeight
    let sign = gutter.collapseSignRect(ofRun: 0)
    #expect(sign.midY == 10.5 * rowHeight)
    #expect(sign.maxX == gutter.bounds.maxX)
    #expect(sign.width >= 20 && sign.height >= 20)

    var bitmap = try Rendering.bitmap(of: pane)
    #expect(try !Self.hasInk(in: bitmap, rect: sign, of: gutter))

    gutter.pointerMoved(to: CGPoint(x: 10, y: 25.5 * rowHeight))
    #expect(gutter.isShowingCollapseSign(ofRun: 0))
    bitmap = try Rendering.bitmap(of: pane)
    #expect(try Self.hasInk(in: bitmap, rect: sign, of: gutter))

    // Rows outside the run, and other runs, show no sign.
    gutter.pointerMoved(to: CGPoint(x: 10, y: 5.5 * rowHeight))
    #expect(gutter.hoveredRun == nil)
    gutter.pointerMoved(to: CGPoint(x: 10, y: 33.5 * rowHeight))
    #expect(gutter.hoveredRun == 1)
  }

  @Test func clickOnTheSignAsksToCollapseItsRunAndAClickBesideItNamesTheRow() throws {
    let (pane, window, recorder) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let rowHeight = pane.theme.rowHeight
    gutter.pointerMoved(to: CGPoint(x: 10, y: 12.5 * rowHeight))
    let sign = gutter.collapseSignRect(ofRun: 0)

    try Clicking.click(gutter, at: CGPoint(x: sign.midX, y: sign.midY))
    try Clicking.click(gutter, at: CGPoint(x: 4, y: 12.5 * rowHeight))

    #expect(recorder.collapses == [CollapsedRun(rows: 10..<30)])
    #expect(recorder.clicks == [12])
    // The pane leaves the run expanded until its owner collapses it.
    #expect(pane.collapsedRuns.isEmpty)
  }

  @Test func voiceOverFindsAButtonThatCollapsesEachExpandedRunInView() throws {
    let (pane, window, recorder) = Self.pane()
    defer { window.close() }
    let elements = try #require(
      pane.gutterView.accessibilityChildren() as? [NSAccessibilityElement])
    let buttons = elements.filter { $0.accessibilityRole() == .button }
    try #require(buttons.count == 2)
    #expect(buttons[0].accessibilityLabel() == "Collapse 20 Unchanged Lines")
    #expect(buttons[0].accessibilityValue() as? String == "Line 11")
    #expect(buttons[1].accessibilityLabel() == "Collapse 8 Unchanged Lines")
    #expect(buttons[1].accessibilityPerformPress())
    #expect(recorder.collapses == [CollapsedRun(rows: 32..<40)])
  }

  @Test func signExplainsItselfInAHelpTagAndToVoiceOver() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    gutter.pointerMoved(to: CGPoint(x: 10, y: 12.5 * pane.theme.rowHeight))
    let sign = gutter.collapseSignRect(ofRun: 0)
    let help = gutter.view(
      gutter, stringForToolTip: 0, point: CGPoint(x: sign.midX, y: sign.midY), userData: nil)
    #expect(help == "Collapses these unchanged lines again")
    let elements = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(elements.first { $0.accessibilityRole() == .button }?.accessibilityHelp() == help)
  }

  @Test func newContentDropsExpandedRunsThatNoLongerFit() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    pane.content = CodeRows.content(count: 5)
    #expect(pane.expandedRuns.isEmpty)
  }

  /// Forty rows of code with two expanded runs, in a pane that shows all of them, and the
  /// delegate that records what the pane asks for.
  private static func pane() -> (PaneView, NSWindow, CollapseRecorder) {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 40)
    pane.expandedRuns = [CollapsedRun(rows: 10..<30), CollapsedRun(rows: 32..<40)]
    let recorder = CollapseRecorder()
    pane.delegate = recorder
    let window = Rendering.host(
      pane, size: CGSize(width: 600, height: 900), appearance: Look.all[0].appearance)
    return (pane, window, recorder)
  }

  /// Whether `rect` of `gutter` holds anything other than the background in `bitmap` of the
  /// pane.
  private static func hasInk(
    in bitmap: NSBitmapImageRep, rect: CGRect, of gutter: NSView
  ) throws -> Bool {
    let area = gutter.convert(rect, to: gutter.superview)
    let background = try Rendering.color(in: bitmap, at: CGPoint(x: area.minX, y: 1))
    for y in stride(from: area.minY, to: area.maxY, by: 1) {
      for x in stride(from: area.minX, to: area.maxX, by: 1) {
        let color = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y))
        if abs(color.redComponent - background.redComponent) > 0.2 {
          return true
        }
      }
    }
    return false
  }
}

/// Records the clicks and the requests to collapse that a pane reports.
@MainActor
private final class CollapseRecorder: PaneViewDelegate {
  var clicks: [Int] = []
  var collapses: [CollapsedRun] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    clicks.append(hit.row)
  }

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? { nil }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {}

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {
    collapses.append(run)
  }
}
