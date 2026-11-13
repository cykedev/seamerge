import MergeModel
import Testing

/// Toggles and the other commands that choose the sources of a block.
struct ToggleTests {
  @Test func switchingOnAppendsTheSourceAfterThoseAlreadyOn() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]

    buffer.perform(buffer.document.planToggling(.a, in: conflict))
    #expect(buffer.text(of: conflict) == "A3\n")
    #expect(buffer.document.segment(for: conflict).state == .chosen)

    buffer.perform(buffer.document.planToggling(.b, in: conflict))
    #expect(buffer.text(of: conflict) == "A3\nB3\n")
    #expect(buffer.document.segment(for: conflict).sources == [.a, .b])

    var reversed = try await ResultBuffer(MergeFixture.nineBlocks())
    reversed.perform(reversed.document.planToggling(.b, in: conflict))
    reversed.perform(reversed.document.planToggling(.a, in: conflict))
    #expect(reversed.text(of: conflict) == "B3\nA3\n")
    reversed.checkInvariants()
  }

  @Test func switchingOffTakesTheSourceOut() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    buffer.perform(buffer.document.planChoosing([.a, .base, .b], in: conflict))
    #expect(buffer.text(of: conflict) == "A3\nx3\nB3\n")

    buffer.perform(buffer.document.planToggling(.base, in: conflict))

    #expect(buffer.text(of: conflict) == "A3\nB3\n")
    #expect(buffer.document.segment(for: conflict).sources == [.a, .b])
  }

  @Test func switchingOffEveryToggleReopensAConflict() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    buffer.perform(buffer.document.planToggling(.a, in: conflict))
    #expect(buffer.document.openConflictCount == 1)

    buffer.perform(buffer.document.planToggling(.a, in: conflict))

    #expect(buffer.document.segment(for: conflict).state == .open)
    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.openConflictCount == 2)
  }

  @Test func lastToggleOfABlockThatIsNoConflictStaysOn() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let changed = buffer.blocks[1]

    #expect(buffer.document.planToggling(.a, in: changed).isEmpty)

    buffer.perform(buffer.document.planToggling(.base, in: changed))
    #expect(buffer.text(of: changed) == "A1\nx1\n")
    #expect(buffer.document.segment(for: changed).sources == [.a, .base, .b])

    buffer.perform(buffer.document.planToggling(.a, in: changed))
    #expect(buffer.text(of: changed) == "x1\n")
    #expect(buffer.document.planToggling(.b, in: changed).isEmpty)
  }

  @Test func equalVersionsShareAToggle() async throws {
    let nine = ResultDocument(session: try await MergeFixture.nineBlocks())
    #expect(nine.toggles(in: nine.session.blocks[0]).map(\.roles) == [[.base, .a, .b]])
    #expect(nine.toggles(in: nine.session.blocks[1]).map(\.roles) == [[.base, .b], [.a]])
    #expect(nine.toggles(in: nine.session.blocks[3]).map(\.roles) == [[.base], [.a], [.b]])

    let same = ResultDocument(session: try await MergeFixture.sameChange())
    #expect(same.toggles(in: same.session.blocks[1]).map(\.roles) == [[.base], [.a, .b]])
  }

  @Test func choicesOfSharedTogglesOrAroundADeletionGiveTheSameSources() async throws {
    let nine = ResultDocument(session: try await MergeFixture.nineBlocks())
    // A changed block 1; the base and B share a toggle.
    let changedInA = nine.session.blocks[1]
    #expect(nine.sourcesChoosing([.b], in: changedInA) == [.base, .b])
    #expect(nine.sourcesChoosing([.base], in: changedInA) == [.base, .b])
    #expect(nine.sourcesChoosing([.a, .b], in: changedInA) == [.a, .base, .b])
    // A removed the lines of block 7: its toggle switches the others off.
    let deletion = nine.session.blocks[7]
    #expect(nine.sourcesChoosing([.a, .b], in: deletion) == [.b])
    #expect(nine.sourcesChoosing([.b, .a], in: deletion) == [.a])
    #expect(nine.sourcesChoosing([], in: deletion) == [])

    let same = ResultDocument(session: try await MergeFixture.sameChange())
    let both = same.session.blocks[1]
    for roles: [Role] in [[.a], [.b], [.a, .b], [.b, .a]] {
      #expect(same.sourcesChoosing(roles, in: both) == [.a, .b], "\(roles)")
    }
  }

  @Test func versionsThatDifferOnlyInIgnoredWhitespaceKeepSeparateToggles() async throws {
    let session = try await merge(
      base: "u0\nx1\n", a: "u0 \ny1\n", b: "u0\t\ny1\t\n", mode: .ignoreWhitespaceAmount)
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInBoth])
    var buffer = ResultBuffer(session)

    #expect(buffer.document.toggles(in: buffer.blocks[0]).map(\.roles) == [[.base], [.a], [.b]])
    #expect(buffer.document.toggles(in: buffer.blocks[1]).map(\.roles) == [[.base], [.a], [.b]])

    // In an unchanged block, choosing a source chooses whose whitespace counts.
    buffer.perform(buffer.document.planChoosing([.a], in: buffer.blocks[0]))
    #expect(buffer.text(of: buffer.blocks[0]) == "u0 \n")
    #expect(buffer.document.segments[0].state == .chosen)
  }

  @Test func followingADeletionEmptiesTheBlockAndSwitchesTheOthersOff() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[7]
    buffer.perform(buffer.document.planChoosing([.base, .b], in: conflict))
    #expect(buffer.text(of: conflict) == "x7\nY7\n")

    buffer.perform(buffer.document.planToggling(.a, in: conflict))
    #expect(buffer.text(of: conflict) == "")
    #expect(buffer.document.segment(for: conflict).sources == [.a])
    #expect(buffer.document.segment(for: conflict).state == .chosen)

    buffer.perform(buffer.document.planToggling(.b, in: conflict))
    #expect(buffer.text(of: conflict) == "Y7\n")
    #expect(buffer.document.segment(for: conflict).sources == [.b])
    buffer.checkInvariants()
  }

  @Test func everyToggleKnowsWhetherItTakesAVersionOrADeletion() async throws {
    let nine = ResultDocument(session: try await MergeFixture.nineBlocks())
    let toggles = nine.toggles(in: nine.session.blocks[7])
    #expect(toggles.map(\.roles) == [[.base], [.a], [.b]])
    #expect(toggles.map(\.kind) == [.version, .deletion, .version])
    #expect(toggles.map(\.isExclusive) == [false, true, false])

    // Not taking an insertion is no deletion, but it is still exclusive.
    let session = try await merge(base: "u0\n", a: "u0\nn1\n", b: "u0\n")
    try #require(session.blocks.map(\.kind) == [.unchanged, .changedInA])
    let insertion = ResultDocument(session: session).toggles(in: session.blocks[1])
    #expect(insertion.map(\.roles) == [[.base, .b], [.a]])
    #expect(insertion.map(\.kind) == [.version, .version])
    #expect(insertion.map(\.isExclusive) == [true, false])
  }

  @Test func takingNothingEmptiesTheBlockAndResolvesAConflict() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]

    buffer.perform(buffer.document.planChoosing([], in: conflict))

    #expect(buffer.text(of: conflict) == "")
    #expect(buffer.document.segment(for: conflict).state == .chosen)
    #expect(buffer.document.segment(for: conflict).sources.isEmpty)
    #expect(buffer.document.openConflictCount == 1)
    #expect(buffer.document.planChoosing([], in: conflict).isEmpty)
  }

  @Test func takingOnlyOneSourceSwitchesTheOthersOff() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]
    buffer.perform(buffer.document.planChoosing([.a, .b], in: conflict))

    buffer.perform(buffer.document.planChoosing([.b], in: conflict))

    #expect(buffer.text(of: conflict) == "B3\n")
    #expect(buffer.document.segment(for: conflict).sources == [.b])
  }

  @Test func choosingTwoSourcesTakesThemInTheGivenOrder() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]

    buffer.perform(buffer.document.planChoosing([.b, .a], in: conflict))

    #expect(buffer.text(of: conflict) == "B3\nA3\n")
    #expect(buffer.undoStack.count == 1)
  }

  @Test func choosingASourceReplacesWhateverTheSegmentHolds() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let changed = buffer.blocks[1]
    buffer.type("hand-written ", at: 3)

    buffer.perform(buffer.document.planChoosing([.b], in: changed))

    #expect(buffer.text(of: changed) == "x1\n")
    #expect(buffer.document.segment(for: changed).state == .chosen)
    buffer.undo()
    #expect(buffer.text(of: changed) == "hand-written A1\n")
  }

  @Test func switchingOnTheOnlyToggleAgainRestoresAnEditedBlock() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let changed = buffer.blocks[1]
    buffer.type("z", at: 4)

    buffer.perform(buffer.document.planToggling(.a, in: changed))

    #expect(buffer.text(of: changed) == "A1\n")
    #expect(buffer.document.segment(for: changed).state == .auto)
    #expect(buffer.document.segment(for: changed).sources == [.a])
  }

  @Test func choosingTheSourcesABlockWasLoadedWithMakesItAutomaticAgain() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let changed = buffer.blocks[1]
    let unchanged = buffer.blocks[2]
    buffer.perform(buffer.document.planChoosing([.b], in: changed))
    buffer.perform(buffer.document.planChoosing([.base], in: unchanged))
    #expect(buffer.document.canReset(changed))

    buffer.perform(buffer.document.planChoosing([.a], in: changed))
    buffer.perform(buffer.document.planToggling(.b, in: unchanged))

    #expect(buffer.document.segment(for: changed).state == .auto)
    #expect(buffer.document.segment(for: unchanged).state == .untouched)
    #expect(!buffer.document.canResetAll)
    #expect(buffer.text == MergeFixture.nineBlocksText)
    #expect(buffer.document.planChoosing([.a], in: changed).isEmpty)
  }

  @Test func resolvingAllOpenConflictsLeavesDecidedBlocksAlone() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    buffer.perform(buffer.document.planChoosing([.b], in: buffer.blocks[3]))

    buffer.perform(buffer.document.planResolvingOpenConflicts(with: [.a]))

    #expect(buffer.text(of: buffer.blocks[3]) == "B3\n")
    #expect(buffer.text(of: buffer.blocks[7]) == "")
    #expect(buffer.document.segments[7].sources == [.a])
    #expect(buffer.document.openConflictCount == 0)
    #expect(buffer.undoStack.count == 2)
    #expect(buffer.document.planResolvingOpenConflicts(with: [.b]).isEmpty)
  }

  @Test func resolvingByHandTurnsThePreviewIntoText() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let conflict = buffer.blocks[3]

    let resolution = buffer.document.planResolvingByHand(conflict)
    buffer.perform(resolution.plan)

    #expect(resolution.plan.replacements.isEmpty)
    #expect(resolution.cursorPosition == 9)
    #expect(buffer.text(of: conflict) == "A3\nB3\n")
    #expect(buffer.document.segment(for: conflict).state == .edited)
    buffer.type("+", at: 12)
    #expect(buffer.text(of: conflict) == "A3\n+B3\n")
  }

  @Test func resolvingAnEmptyBlockByHandGivesItAnEmptyLine() async throws {
    var buffer = try await ResultBuffer(MergeFixture.nineBlocks())
    let block = buffer.blocks[5]
    buffer.perform(buffer.document.planChoosing([], in: block))

    let resolution = buffer.document.planResolvingByHand(block)
    buffer.perform(resolution.plan)
    #expect(resolution.cursorPosition == 18)
    #expect(buffer.text(of: block) == "\n")
    #expect(buffer.document.segment(for: block).state == .edited)

    buffer.type("z", at: 18)
    #expect(buffer.text(of: block) == "z\n")
  }

  @Test func resolvingByHandLeavesTextAsItIsAndPutsTheCursorAtTheStart() async throws {
    let document = ResultDocument(session: try await MergeFixture.nineBlocks())

    let resolution = document.planResolvingByHand(document.session.blocks[1])

    #expect(resolution.plan.isEmpty)
    #expect(resolution.cursorPosition == 3)
  }
}
