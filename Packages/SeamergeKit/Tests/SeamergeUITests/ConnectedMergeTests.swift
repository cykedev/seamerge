import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// The merge window with Align Lines turned off: A, Base and B show their files without filler
/// rows, seams connect A with Base and Base with B, or A with B while the base is hidden, and
/// the panes side by side and the result scroll over a common track.
@MainActor
@Suite(.serialized) struct ConnectedMergeTests {
  @Test func withoutTheBaseOneSeamConnectsAWithB() async throws {
    let controller = try await connectedWindow()
    let layout = controller.layout
    let (a, base, b) = try panes(of: controller)
    #expect(layout.seams.map { [$0.leftPane, $0.rightPane] } == [[a, base], [base, b]])
    controller.toggleBase(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    #expect(layout.seams.map { [$0.leftPane, $0.rightPane] } == [[a, b]])
    let gap = b.convert(b.bounds, to: nil).minX - a.convert(a.bounds, to: nil).maxX
    #expect(gap == Theme.seamWidth)
    #expect(layout.seams.first?.frame.width == Theme.seamWidth)
    controller.toggleBase(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    #expect(layout.seams.map { [$0.leftPane, $0.rightPane] } == [[a, base], [base, b]])
  }

  @Test(arguments: [true, false], [false, true])
  func everyPaneScrolledByHandTakesTheOthersAlongSteadilyOnTheTrack(
    showsBase: Bool, wraps: Bool
  ) async throws {
    let controller = try await connectedWindow()
    if wraps {
      controller.toggleLineWrapping(nil)
    }
    if !showsBase {
      controller.toggleBase(nil)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }
    let (a, base, b) = try panes(of: controller)
    let result = try controller.mergeResult
    let panes = showsBase ? [a, base, b, result] : [a, b, result]
    let track = try #require(ScrollTrack(panes: panes))
    for leader in panes {
      let step = leader.rowHeight / 2
      var steps = 0
      // From a place where the panes stand together on the track; at the very top, the reading
      // lines of panes of different heights lie apart on it.
      leader.placeReadingLine(at: leader.readingLinePlace + 10 * leader.rowHeight, x: 0)
      for direction in [1.0, -1.0] {
        var places = panes.map(\.readingLinePlace)
        leader.textView.liveScrollDidStart()
        while steps < 20_000 {
          let origin = leader.documentView.visibleRect.origin
          leader.documentView.scroll(CGPoint(x: 0, y: origin.y + direction * step))
          let now = panes.map(\.readingLinePlace)
          let moves = zip(now, places).map { ($0 - $1) * direction }
          #expect(
            moves.allSatisfy { $0 >= -0.001 && $0 <= leader.rowHeight },
            "\(moves) at step \(steps), \(direction)")
          // Panes at the top or the end of their texts may stand short of the track.
          if !panes.contains(where: atAnEnd) {
            let positions = now.indices.map { track.trackPositions(ofPane: $0, atPlace: now[$0]) }
            let lowest = positions.map(\.upperBound).min() ?? 0
            let highest = positions.map(\.lowerBound).max() ?? 0
            #expect(highest <= lowest + 0.5, "the panes stand together: \(positions)")
          }
          guard moves.contains(where: { $0 > 0.001 }) else { break }
          places = now
          steps += 1
        }
        leader.textView.liveScrollDidEnd()
      }
      #expect(steps > 200)
    }
  }

  @Test func jumpBringsTheBlockToTheReadingLineOfEveryPane() async throws {
    let controller = try await connectedWindow()
    let (a, base, b) = try panes(of: controller)
    let result = try controller.mergeResult
    let blocks = controller.presentation.changes.blocks
    // A block deep in the file that only A inserts: the base and B stand on its hairline.
    let insertion = try #require(
      blocks.indices.last { blocks[$0].kind == .changedInA && blocks[$0].lines(in: .b).isEmpty })
    controller.presentation.jump(to: insertion)
    for pane in [a, base, b, result] {
      let span = pane.verticalSpan(ofRows: pane.content.blocks[insertion].rows)
      #expect(
        span.lowerBound - 0.5 <= pane.readingLinePlace
          && pane.readingLinePlace <= span.upperBound + 0.5,
        "\(span) holds \(pane.readingLinePlace)")
    }
  }

  @Test func resultThatScrollsToItsInsertionPointTakesThePanesAboveAlong() async throws {
    let controller = try await connectedWindow()
    let result = try controller.mergeResult
    let (a, base, b) = try panes(of: controller)
    let text = result.documentView
    controller.window?.makeFirstResponder(text)
    text.setSelectedRange(NSRange(location: (text.string as NSString).length * 2 / 3, length: 0))
    text.scrollRangeToVisible(text.selectedRange())
    let panes = [a, base, b, result]
    // The track as the panes show their rows now, the run of the insertion point expanded.
    let track = try #require(ScrollTrack(panes: panes))
    let positions = panes.indices.map {
      track.trackPositions(ofPane: $0, atPlace: panes[$0].readingLinePlace)
    }
    #expect(
      (positions.map(\.lowerBound).max() ?? 0) <= (positions.map(\.upperBound).min() ?? 0) + 0.5,
      "\(positions)")
  }

  @Test func seamsShowBandsOnlyWhereTheirPanesDiffer() async throws {
    let controller = try await connectedWindow()
    let changes = controller.presentation.changes
    let seams = controller.layout.seams
    try #require(seams.count == 2)
    let onlyA = changes.blocks.indices.filter { changes.blocks[$0].kind == .changedInA }
    let onlyB = changes.blocks.indices.filter { changes.blocks[$0].kind == .changedInB }
    try #require(!onlyA.isEmpty && !onlyB.isEmpty)
    #expect(seams[0].blocksWithoutBand == IndexSet(onlyB))
    #expect(seams[1].blocksWithoutBand == IndexSet(onlyA))
    controller.toggleBase(nil)
    let both = changes.blocks.indices.filter { changes.blocks[$0].kind == .changedInBoth }
    try #require(!both.isEmpty)
    #expect(controller.layout.seams.first?.blocksWithoutBand == IndexSet(both))
  }

  @Test func alignLinesSwitchesTheMergeAndKeepsTheBlockAtTheReadingLine() async throws {
    let controller = try await connectedWindow()
    let (a, base, b) = try panes(of: controller)
    #expect(!controller.presentation.alignsLines)
    #expect(![a, base, b].contains { $0.content.lineNumbers.contains(-1) })
    let block = controller.presentation.changes.blocks.count / 2
    controller.presentation.jump(to: block)
    controller.toggleLineAlignment(nil)
    #expect(controller.presentation.alignsLines && controller.layout.seams.isEmpty)
    #expect(base.content.lineNumbers.contains(-1))
    #expect(controller.presentation.currentBlock == block)
    let rows = b.content.blocks[block].rows
    let span = b.verticalSpan(ofRows: rows)
    #expect(span.lowerBound - 0.5 <= b.readingLinePlace && b.readingLinePlace <= span.upperBound)
    controller.toggleLineAlignment(nil)
    #expect(controller.layout.seams.count == 2)
  }

  @Test func maximizedResultTakesThePanesAboveAlongWhenItGivesTheRoomBack() async throws {
    let controller = try await connectedWindow()
    let result = try controller.mergeResult
    let (a, base, b) = try panes(of: controller)
    controller.toggleResultMaximized(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let text = result.documentView
    text.scroll(CGPoint(x: 0, y: text.frame.height / 2))
    controller.toggleResultMaximized(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let panes = [a, base, b, result]
    let track = try #require(ScrollTrack(panes: panes))
    let positions = panes.indices.map {
      track.trackPositions(ofPane: $0, atPlace: panes[$0].readingLinePlace)
    }
    #expect(
      (positions.map(\.lowerBound).max() ?? 0) <= (positions.map(\.upperBound).min() ?? 0) + 0.5,
      "\(positions)")
  }

  /// A window of the example merge with Align Lines off.
  private func connectedWindow() async throws -> SessionWindowController {
    let settings = UserSettings.private()
    settings.alignsLines = false
    let controller = try Windows.controller(
      for: try await SampleMerges.example(), settings: settings)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  /// Whether `pane` stands at the top or the end of its text.
  private func atAnEnd(_ pane: PaneView) -> Bool {
    let text = pane.documentView
    return text.visibleRect.minY <= 0 || text.visibleRect.maxY >= text.frame.height - 1
  }

  private func panes(of controller: SessionWindowController) throws -> (
    PaneView, PaneView, PaneView
  ) {
    (
      try #require(controller.layout.sourcePane(.a)),
      try #require(controller.layout.sourcePane(.base)),
      try #require(controller.layout.sourcePane(.b))
    )
  }
}
