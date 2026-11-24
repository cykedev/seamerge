import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A merge window that keeps its work on disk: a second after each step at most once a second,
/// at once as it closes and before it reports its end, and never once the merge is finished.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MergeWorkKeepingTests {
  @Test func decisionIsKeptOnceTheTimerFires() async throws {
    let merge = try await WorkingMerge()
    #expect(!merge.work.timer.isScheduled)

    merge.decide(0, .useB)
    #expect(merge.work.timer.delays == [.seconds(1)])
    #expect(try await merge.keptWork == nil)

    await merge.keepOnTime()
    let work = try #require(try await merge.keptWork)
    #expect(work.savedAt == WorkFolder.start)
    #expect(work.mode == .windowDefault)
    merge.controller.leaveUnresolved(nil)
    await merge.ended()
  }

  @Test func typedTextIsKeptOnceTheTimerFires() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useB)
    await merge.keepOnTime()
    let text = try merge.controller.mergeResult.documentView.string
    let range = try #require(text.range(of: "B 1"))
    let offset = text.utf16.distance(from: text.startIndex, to: range.lowerBound)

    try merge.controller.type("typed ", over: offset..<offset, with: .insertText)
    merge.controller.endEvent()
    #expect(merge.work.timer.isScheduled)
    await merge.keepOnTime()

    let restored = try await reopened(merge)
    #expect(try restored.controller.segmentTexts.contains("typed B 1\n"))
    await merge.close()
    await restored.close()
  }

  @Test func switchOfTheComparisonModeIsKeptOnceTheTimerFires() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useA)
    await merge.keepOnTime()

    await merge.controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    #expect(merge.work.timer.isScheduled)
    await merge.keepOnTime()

    #expect(try await merge.keptWork?.mode == .ignoreAllWhitespace)
    merge.controller.leaveUnresolved(nil)
    await merge.ended()
  }

  @Test func choiceOfTheEncodingIsKeptOnceTheTimerFires() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useB)
    await merge.keepOnTime()

    merge.controller.choose(.encoding(.utf16LittleEndian))
    #expect(merge.work.timer.isScheduled)
    await merge.keepOnTime()

    #expect(try await merge.keptWork?.format.encoding == .utf16LittleEndian)
    merge.controller.leaveUnresolved(nil)
    await merge.ended()
  }

  @Test func stepsWithinASecondAreKeptTogether() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useA)
    merge.decide(1, .useB)
    merge.decide(2, .useBase)
    #expect(merge.work.timer.delays == [.seconds(1)])

    await merge.keepOnTime()
    #expect(try merge.conflictSegments.allSatisfy { !$0.hasPrefix("open") })
    #expect(try await merge.keptWork != nil)
    // Nothing changed since: the next second writes nothing and waits for nothing.
    #expect(!merge.work.timer.isScheduled)
    merge.decide(0, .useB)
    #expect(merge.work.timer.delays == [.seconds(1), .seconds(1)])
    merge.controller.leaveUnresolved(nil)
    await merge.ended()
  }

  @Test func resultAsLoadedLeavesNoWork() async throws {
    let merge = try await WorkingMerge()
    await merge.controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    await merge.keepOnTime()
    #expect(try merge.work.fileNames.isEmpty)

    merge.prompts.unsavedChangesChoice = .discard
    #expect(await merge.controller.closeAskingFirst())
    await merge.ended()
    #expect(merge.heldWorkAtTheEnd == [false])
    #expect(try merge.work.fileNames.isEmpty)
  }

  @Test func closingWithoutSavingKeepsTheWorkBeforeTheCallerHears() async throws {
    let merge = try await WorkingMerge()
    merge.decide(1, .useB)
    merge.prompts.unsavedChangesChoice = .discard

    #expect(await merge.controller.closeAskingFirst())
    await merge.ended()

    #expect(merge.outcomes == [.cancelled])
    #expect(merge.heldWorkAtTheEnd == [true])
    #expect(try await merge.keptWork != nil)
  }

  @Test func leavingUnresolvedKeepsTheWorkBeforeTheCallerHears() async throws {
    let merge = try await WorkingMerge()
    merge.decide(1, .useA)

    merge.controller.leaveUnresolved(nil)
    await merge.ended()

    #expect(merge.prompts.questions.isEmpty)
    #expect(merge.outcomes == [.cancelled])
    #expect(merge.heldWorkAtTheEnd == [true])
  }

  @Test func savingWithMarkersKeepsTheWork() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useA)
    merge.prompts.openConflictsChoice = .saveWithMarkers

    #expect(await merge.controller.saveAndCloseWindow())
    await merge.ended()

    #expect(merge.outcomes == [.saved])
    #expect(merge.heldWorkAtTheEnd == [true])
  }

  @Test func quittingKeepsTheWorkBeforeTheCallerHears() async throws {
    let asked = try await WorkingMerge()
    asked.decide(0, .useB)
    asked.prompts.unsavedChangesChoice = .discard
    #expect(await asked.controller.closeAskingFirst(asTheAppQuits: true))
    await asked.ended()
    #expect(asked.heldWorkAtTheEnd == [true])

    let closed = try await WorkingMerge(work: asked.work)
    try FileManager.default.removeItem(at: asked.work.url)
    closed.decide(2, .useA)
    closed.controller.closeAsTheAppQuits()
    await closed.ended()
    #expect(closed.outcomes == [.cancelled])
    #expect(closed.heldWorkAtTheEnd == [true])
  }

  @Test func finishingTheMergeRemovesItsWorkBeforeTheCallerHears() async throws {
    let merge = try await WorkingMerge()
    for number in 0..<3 {
      merge.decide(number, .useB)
    }
    await merge.keepOnTime()
    #expect(try await merge.keptWork != nil)

    #expect(await merge.controller.saveAndCloseWindow())
    await merge.ended()

    #expect(merge.outcomes == [.saved])
    #expect(merge.heldWorkAtTheEnd == [false])
    #expect(try merge.work.fileNames.isEmpty)
  }

  @Test func finishingRightAfterASwitchOfTheComparisonModeRemovesTheWork() async throws {
    let merge = try await WorkingMerge()
    for number in 0..<3 {
      merge.decide(number, .useB)
    }
    await merge.keepOnTime()
    #expect(try await merge.keptWork != nil)

    // The same files compared anew are the same merge; Done within the second after the switch
    // still knows that the folder holds its work.
    await merge.controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    #expect(await merge.controller.saveAndCloseWindow())
    await merge.ended()

    #expect(merge.outcomes == [.saved])
    #expect(merge.heldWorkAtTheEnd == [false])
    #expect(try merge.work.fileNames.isEmpty)
  }

  @Test func savingThenClosingFinishesTheMerge() async throws {
    let merge = try await WorkingMerge()
    for number in 0..<3 {
      merge.decide(number, .useA)
    }
    await merge.keepOnTime()
    #expect(await merge.controller.save())
    #expect(try await merge.keptWork != nil)

    await merge.close()

    #expect(merge.outcomes == [.saved])
    #expect(merge.heldWorkAtTheEnd == [false])
  }

  @Test func resettingEveryDecisionRemovesTheWork() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useB)
    merge.decide(2, .useA)
    await merge.keepOnTime()
    #expect(try await merge.keptWork != nil)

    await merge.controller.resetEveryDecision()
    merge.controller.endEvent()
    await merge.keepOnTime()

    #expect(try merge.work.fileNames.isEmpty)
    merge.prompts.unsavedChangesChoice = .discard
    #expect(await merge.controller.closeAskingFirst())
    await merge.ended()
    #expect(merge.heldWorkAtTheEnd == [false])
  }

  @Test func windowLetGoWithoutClosingLeavesTheLastWork() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useA)
    await merge.keepOnTime()
    merge.decide(1, .useB)
    await merge.keepOnTime()
    let expected = try merge.conflictSegments

    // As after a crash: nothing closes, nothing reports; what the timer wrote is all there is.
    let restored = try await reopened(merge)
    #expect(try restored.conflictSegments == expected)
    #expect(merge.outcomes.isEmpty)
    await merge.close()
    await restored.close()
  }

  @Test func twoWindowsOfTheSameMergeKeepTheirWorkSideBySide() async throws {
    let first = try await WorkingMerge()
    let second = try await WorkingMerge(in: first.folder, work: first.work)
    first.decide(0, .useA)
    second.decide(0, .useB)

    // One timer fires both; each writes, and the work written last counts.
    first.work.timer.fire()
    await first.controller.workKeeper?.lastOperation?.value
    await second.controller.workKeeper?.lastOperation?.value
    #expect(try await first.keptWork != nil)

    first.controller.leaveUnresolved(nil)
    await first.ended()
    let reopenedFirst = try await reopened(first)
    #expect(try reopenedFirst.conflictSegments[0] == "chosen: A 1\n")
    await reopenedFirst.close()

    second.controller.leaveUnresolved(nil)
    await second.ended()
    let reopenedSecond = try await reopened(second)
    #expect(try reopenedSecond.conflictSegments[0] == "chosen: B 1\n")
    await reopenedSecond.close()
    #expect(first.outcomes == [.cancelled])
    #expect(second.outcomes == [.cancelled])
    #expect(first.heldWorkAtTheEnd == [true])
    #expect(second.heldWorkAtTheEnd == [true])
  }

  @Test func workOfReloadedFilesIsKeptUnderTheirOwnKey() async throws {
    let merge = try await WorkingMerge()
    merge.decide(0, .useB)
    await merge.keepOnTime()
    let before = try #require(try await merge.keptWork)

    let changedB = WorkingMerge.b.replacingOccurrences(of: "four", with: "four and more")
    try Data(changedB.utf8).write(to: merge.folder.appending(path: "b.txt"), options: .atomic)
    merge.prompts.reloadsAnyway = true
    await merge.controller.diskWatch.reloadChangedFiles()
    merge.controller.endEvent()
    await merge.keepOnTime()

    let reloaded = merge.controller.presentation.changes.session.inputs
    #expect(try await merge.work.work(of: reloaded) != nil)
    #expect(try await merge.keptWork == before)
    #expect(try merge.work.fileNames.count == 2)
    merge.controller.leaveUnresolved(nil)
    await merge.ended()
  }

  @Test func waitingWindowKeepsNothingUntilItIsFilled() async throws {
    let work = WorkFolder()
    let keeper = work.keeper()
    let files = Session.Inputs(
      base: SessionFile(url: URL(filePath: "/tmp/none/base.txt"), label: "base.txt"),
      a: SessionFile(url: URL(filePath: "/tmp/none/a.txt"), label: "a.txt"),
      b: SessionFile(url: URL(filePath: "/tmp/none/b.txt"), label: "b.txt"))
    let empty = try await SessionWindowController.emptySession(
      of: files, kind: .merge, mode: .windowDefault)
    let comparison = PendingComparison { .failure(.comparisonFailed) }
    let controller = try Windows.controller(
      for: empty, pendingComparison: comparison, workKeeper: keeper)
    #expect(controller.workSnapshot == nil)

    controller.close()
    await keeper.lastOperation?.value
    #expect(try work.fileNames.isEmpty)
  }

  /// A window of the merge of `merge` in a folder of its own, under other names, which puts back
  /// the work kept for it.
  private func reopened(_ merge: WorkingMerge) async throws -> RestoredMerge {
    try await RestoredMerge(copying: merge)
  }
}
