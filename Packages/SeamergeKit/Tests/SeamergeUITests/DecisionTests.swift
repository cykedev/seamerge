import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Deciding blocks in the window: every kind of decision, the order of toggles, choosing after
/// typing, going on to the next open conflict, and the validity of the commands.
@MainActor
@Suite struct DecisionTests {
  @Test(arguments: [
    (SessionCommand.useA, "A3\n"), (.useBase, "x3\n"), (.useB, "B3\n"),
    (.useAThenB, "A3\nB3\n"), (.useBThenA, "B3\nA3\n"), (.useNone, ""),
  ])
  func everyDecisionTakesTheTextsOfItsSources(command: SessionCommand, text: String) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(1)

    #expect(controller.canPerform(command))
    controller.perform(command)

    #expect(try controller.segmentTexts[3] == text)
    #expect(try controller.segmentStates[3] == .chosen)
    #expect(try controller.presentation.mergeResult.document.openConflictCount == 1)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func choosingBAfterTypingSetsTheSegmentExactlyToB() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    try controller.type("typed", over: 4..<4, with: .insertText)
    #expect(controller.presentation.currentBlock == 0)
    #expect(try controller.segmentStates[1] == .edited)

    controller.perform(.useB)

    #expect(try controller.segmentTexts[1] == "x1\n")
    #expect(try controller.segmentStates[1] == .chosen)
    #expect(try controller.mergeResult.content.rowTints.isEmpty)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func switchingOnAThenBTakesAThenBAndTheOtherWayRound() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(1)

    controller.perform(.toggleSourceA)
    controller.perform(.toggleSourceB)
    #expect(try controller.segmentTexts[3] == "A3\nB3\n")
    // A toggle keeps the block current, so that further toggles add to it.
    #expect(controller.presentation.currentBlock == 1)

    // Switching off again leaves the conflict open, ready for the other order.
    controller.perform(.toggleSourceB)
    controller.perform(.toggleSourceA)
    #expect(try controller.segmentStates[3] == .open)
    controller.perform(.toggleSourceB)
    controller.perform(.toggleSourceA)
    #expect(try controller.segmentTexts[3] == "B3\nA3\n")
    try controller.checkResultIsShownAsModelled()
  }

  @Test func eachLineOfABlockOfSeveralSourcesIsTintedInTheColorOfItsSource() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(1)

    controller.perform(.useBThenA)

    let pane = try controller.mergeResult
    let rows = pane.content.blocks[1].rows
    #expect(rows.map { pane.content.rowTints[$0] } == [.tinted(.b), .tinted(.a)])
    try controller.checkResultIsShownAsModelled()
  }

  @Test func linesOfAConflictTakenFromOneSideKeepItsTintWhenTypedIn() async throws {
    let session = try await SampleMerges.merge(
      base: "u\nx0\nx1\nu\n", a: "u\nA0\nA1\nu\n", b: "u\nB0\nB1\nu\n")
    let controller = try Windows.controller(for: session)
    controller.perform(.useB)

    try controller.type("!", over: 2..<2, with: .insertText)

    #expect(try controller.mergeResult.content.rowTints == [1: .handwritten, 2: .tinted(.b)])
  }

  @Test func conflictResolvedByHandTintsEachLineInTheColorOfItsSide() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(1)

    controller.perform(.resolveManually)

    let pane = try controller.mergeResult
    let rows = pane.content.blocks[1].rows
    #expect(rows.map { pane.content.rowTints[$0] } == [.tinted(.a), .tinted(.b)])
  }

  @Test func togglesOfTheDecisionColumnDecideAsTheirCommandsDo() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let column = try controller.presentation.mergeDecisionColumn

    // The toggles of the conflict: A, the base, B.
    controller.presentation.decisionColumn(column, didSwitchToggle: 2, ofBlock: 1)

    #expect(try controller.segmentTexts[3] == "B3\n")
    #expect(controller.presentation.currentBlock == 1)
    #expect(column.decisions[1]?.state == .chosen([.b]))
    try controller.checkResultIsShownAsModelled()
  }

  @Test func followingARemovalEmptiesTheBlockAndItsNoteLeaves() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(3)

    controller.perform(.useA)

    #expect(try controller.segmentTexts[7].isEmpty)
    #expect(try controller.mergeResult.content.text.contains(EditingFixture.removalNote) == false)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func commandsAreValidOnlyWhereTheyHaveAnEffect() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    // Block 1 is taken from A as loaded.
    controller.presentation.setCurrentBlock(0)
    #expect(!controller.canPerform(.useA))
    #expect(controller.canPerform(.useB))
    // The last toggle of a block that is no conflict stays on.
    #expect(!controller.canPerform(.toggleSourceA))
    #expect(controller.canPerform(.resolveAllWithA))
    controller.perform(.resolveAllWithA)
    #expect(!controller.canPerform(.resolveAllWithB))
  }

  @Test func mergeWithoutABaseHasNoBaseToTake() async throws {
    let session = try await SampleMerges.merge(base: nil, a: "one\ntwo\n", b: "one\nthree\n")
    let controller = try Windows.controller(for: session)

    #expect(!controller.canPerform(.useBase))
    #expect(!controller.canPerform(.toggleSourceBase))
    #expect(controller.canPerform(.useA))
  }

  @Test func resolvingByHandTurnsThePreviewIntoTextAndPutsTheCaretAtItsStart() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    controller.presentation.setCurrentBlock(3)

    controller.perform(.resolveManually)

    #expect(controller.isInTextMode)
    #expect(try controller.segmentTexts[7] == "Y7\n")
    #expect(try controller.segmentStates[7] == .edited)
    let start = try controller.presentation.mergeResult.document.range(
      of: controller.presentation.changes.blocks[3]
    ).lowerBound
    #expect(try controller.mergeResult.documentView.selectedRange().location == start)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func returnInBlockModeResolvesByHand() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let window = try #require(controller.window)
    let a = try #require(controller.layout.sourcePane(.a))
    window.makeFirstResponder(a.documentView)
    controller.presentation.setCurrentBlock(1)

    try press("\r", in: controller)

    #expect(controller.isInTextMode)
    #expect(try controller.segmentStates[3] == .edited)
    #expect(try controller.segmentTexts[3] == "A3\nB3\n")
  }

  @Test func singleKeysOfBlockModeDecide() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let window = try #require(controller.window)
    let b = try #require(controller.layout.sourcePane(.b))
    window.makeFirstResponder(b.documentView)
    controller.presentation.setCurrentBlock(1)

    try press(SessionCommand.rightArrow, in: controller)

    #expect(try controller.segmentTexts[3] == "B3\n")
    controller.presentation.setCurrentBlock(3)
    try press("1", modifiers: .option, in: controller)
    #expect(try controller.segmentTexts[7] == "")
  }

  @Test func resolvingEveryOpenConflictTakesOneSide() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    controller.perform(.resolveAllWithB)

    let segments = try controller.segmentTexts
    #expect(segments[3] == "B3\n" && segments[7] == "Y7\n")
    #expect(!controller.canPerform(.resolveAllWithA))
    try controller.checkResultIsShownAsModelled()
  }
}
