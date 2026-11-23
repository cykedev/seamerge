import AppKit
import Testing

@testable import PaneKit

/// Checks the arrow in the gutter at an end of a move: which way it points, that it takes the
/// place of the mark of the change, what its help tag and VoiceOver say, and that a click on it
/// or a press with VoiceOver asks to go to the other end.
@MainActor
@Suite struct MoveArrowTests {
  /// A pane of the left file of a comparison in which the lines 3 to 5 moved down to line 12 of
  /// the right file: block 0 is the place they left, block 1 an unrelated change, and block 2 the
  /// filler rows where the right file has them.
  private static func pane(
    marksBlocksWithoutRows: Bool = false
  ) -> (PaneView, NSWindow, MoveRecorder) {
    let pane = PaneView()
    let recorder = MoveRecorder()
    pane.delegate = recorder
    let lines = (0..<12).map { "let value\($0) = \($0)" }
    pane.content = PaneContent(
      text: (lines + ["", "", ""]).joined(separator: "\n"),
      lineNumbers: (0..<12).map(Int32.init) + [-1, -1, -1],
      blocks: [
        PaneBlock(
          rows: 2..<5, style: .tinted(.a), marker: .removed,
          move: MoveMark(end: .source, otherBlock: 2, otherLine: 11)),
        PaneBlock(rows: 7..<8, style: .tinted(.a), marker: .changed),
        PaneBlock(
          rows: 12..<15, style: .tinted(.b),
          move: MoveMark(end: .destination, otherBlock: 0, otherLine: 2)),
      ])
    let window = Rendering.host(
      pane, size: CGSize(width: 500, height: 400), appearance: Look.all[0].appearance)
    return (pane, window, recorder)
  }

  @Test func arrowPointsDownToAnOtherEndBelowAndUpToOneAbove() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    guard case .move(_, let firstPointsDown, _) = try #require(gutter.marks(ofRow: 2).first?.mark),
      case .move(_, let lastPointsDown, _) = try #require(gutter.marks(ofRow: 12).first?.mark)
    else {
      Issue.record("Both ends of the move carry an arrow")
      return
    }
    #expect(firstPointsDown)
    #expect(!lastPointsDown)
    #expect(MoveMark(end: .source, otherBlock: 3, otherLine: 0).pointsDown(fromBlock: 2))
    #expect(!MoveMark(end: .source, otherBlock: 1, otherLine: 0).pointsDown(fromBlock: 2))
  }

  @Test func arrowTakesThePlaceOfTheMarkOfTheChange() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let marks = pane.gutterView.marks(ofRow: 2)
    #expect(marks.count == 1)
    #expect(marks.allSatisfy { if case .move = $0.mark { true } else { false } })
    // The unrelated change keeps its mark.
    #expect(pane.gutterView.marks(ofRow: 7).map(\.help) == [MarkHelp.marker(.changed)])
  }

  @Test func arrowSaysInItsHelpTagWhereTheLinesWentOrCameFrom() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    var helps: [String] = []
    for row in [2, 12] {
      let slot = gutter.markerSlot(0, in: gutter.rect(ofRow: row))
      helps.append(
        gutter.view(
          gutter, stringForToolTip: 0, point: CGPoint(x: slot.midX, y: slot.midY), userData: nil))
    }
    #expect(helps == ["Moved to line 12", "Moved here from line 3"])
    // The corner of the target of a click, beyond the slot of the arrow, has the help tag too.
    let target = try #require(gutter.moveArrows.first).target
    #expect(
      gutter.view(
        gutter, stringForToolTip: 0, point: CGPoint(x: target.minX + 1, y: target.maxY - 1),
        userData: nil) == "Moved to line 12")
  }

  @Test func clickOnTheArrowAsksToGoToTheOtherEndAndAClickBesideItSelectsTheRow() throws {
    let (pane, window, recorder) = Self.pane()
    defer { window.close() }
    let gutter = pane.gutterView
    let arrows = gutter.moveArrows
    try #require(arrows.map(\.block) == [0, 2])
    for arrow in arrows {
      #expect(arrow.target.width >= 20 && arrow.target.height >= 20)
      #expect(gutter.bounds.contains(arrow.target))
    }
    // The corner of the target, beyond the slot of the arrow, counts too.
    let target = arrows[0].target
    try Clicking.click(gutter, at: CGPoint(x: target.minX + 1, y: target.maxY - 1))
    try Clicking.click(gutter, at: CGPoint(x: 4, y: 2.5 * pane.theme.rowHeight))

    #expect(
      recorder.hits == [
        PaneHit(row: 2, block: 0, isOnMoveArrow: true), PaneHit(row: 2, block: 0),
      ])
  }

  @Test func voiceOverFindsAButtonForEachArrowThatGoesToTheOtherEnd() throws {
    let (pane, window, recorder) = Self.pane()
    defer { window.close() }
    let elements = try #require(
      pane.gutterView.accessibilityChildren() as? [NSAccessibilityElement])
    let buttons = elements.filter { $0.accessibilityRole() == .button }
    try #require(buttons.count == 2)
    #expect(
      buttons.map { $0.accessibilityLabel() } == ["Moved to line 12", "Moved here from line 3"])
    #expect(buttons.map { $0.accessibilityValue() as? String } == ["Line 3", "After line 12"])
    #expect(buttons.allSatisfy { $0.accessibilityHelp() == "Goes to the other end of the move" })
    // No second element names the end as a removal.
    #expect(!elements.contains { $0.accessibilityLabel() == "Removed" })
    #expect(buttons[1].accessibilityPerformPress())
    #expect(recorder.hits == [PaneHit(row: 12, block: 2, isOnMoveArrow: true)])
  }

  @Test func endWithoutRowsShowsItsArrowOnTheHairlineWhereTheLinesAreMissing() throws {
    let pane = PaneView()
    let recorder = MoveRecorder()
    pane.delegate = recorder
    pane.content = PaneContent(
      text: (0..<10).map { "let value\($0) = \($0)" }.joined(separator: "\n"),
      lineNumbers: (0..<10).map(Int32.init),
      blocks: [
        PaneBlock(
          rows: 3..<3, style: .tinted(.a), marker: .removed,
          move: MoveMark(end: .source, otherBlock: 1, otherLine: 6)),
        PaneBlock(
          rows: 6..<8, style: .tinted(.a), marker: .added,
          move: MoveMark(end: .destination, otherBlock: 0, otherLine: 3)),
      ],
      marksBlocksWithoutRows: true)
    let window = Rendering.host(
      pane, size: CGSize(width: 500, height: 300), appearance: Look.all[0].appearance)
    defer { window.close() }
    let gutter = pane.gutterView
    let arrows = gutter.moveArrows
    try #require(arrows.map(\.block) == [1, 0])
    #expect(arrows[1].target.midY == 3 * pane.theme.rowHeight)
    let elements = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    let button = try #require(
      elements.first { $0.accessibilityLabel() == "Moved to line 7" })
    #expect(button.accessibilityValue() as? String == "After line 3")

    try Clicking.click(gutter, at: CGPoint(x: arrows[1].target.midX, y: arrows[1].target.midY))
    #expect(recorder.hits == [PaneHit(row: 3, block: 0, isOnMoveArrow: true)])
  }

  @Test func arrowIsDrawnInTheColorOfItsSide() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: pane)
    let gutter = pane.gutterView
    for (row, role) in [(2, ColorRole.a), (12, .b)] {
      let slot = gutter.convert(
        gutter.markerSlot(0, in: gutter.rect(ofRow: row)), to: gutter.superview)
      let expected = pane.theme.symbolColor(for: role).resolved(in: pane.effectiveAppearance)
      var found = false
      for y in stride(from: slot.minY, to: slot.maxY, by: 0.5) {
        for x in stride(from: slot.minX, to: slot.maxX, by: 0.5) {
          let color = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y))
          if abs(color.redComponent - expected.redComponent) < 0.08
            && abs(color.greenComponent - expected.greenComponent) < 0.08
            && abs(color.blueComponent - expected.blueComponent) < 0.08
          {
            found = true
          }
        }
      }
      #expect(found, "The arrow at row \(row) has the color of side \(role)")
    }
  }
}

/// Records the clicks that a pane reports.
@MainActor
private final class MoveRecorder: PaneViewDelegate {
  var hits: [PaneHit] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    hits.append(hit)
  }

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? { nil }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {}

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {}
}
