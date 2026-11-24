import AppKit
import MergeModel
import PaneKit
import Testing
import TextBasics

@testable import SeamergeUI

/// The same merge opened again finds its work: in the comparison mode and at the block it was
/// left in, named in the subtitle until the first step, told to VoiceOver, and taken back with a
/// single undo.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RestoredWorkTests {
  /// A merge left unresolved with conflict 0 taken from B, conflict 2 from A and text typed into
  /// conflict 2, compared without whitespace changes, with conflict 2 current.
  private func leftMerge(waitingCaller: WaitingCaller? = .git) async throws -> WorkingMerge {
    let merge = try await WorkingMerge(waitingCaller: waitingCaller)
    await merge.controller.switchComparison(to: ComparisonOptions(mode: .ignoreWhitespaceAmount))
    merge.decide(0, .useB)
    merge.decide(2, .useA)
    let text = try merge.controller.mergeResult.documentView.string
    let range = try #require(text.range(of: "A 3"))
    let offset = text.utf16.distance(from: text.startIndex, to: range.upperBound)
    try merge.controller.type(" by hand", over: offset..<offset, with: .insertText)
    merge.controller.endEvent()
    merge.controller.presentation.setCurrentBlock(merge.conflicts[2])
    merge.prompts.unsavedChangesChoice = .discard
    if waitingCaller == nil {
      #expect(await merge.controller.closeAskingFirst())
    } else {
      merge.controller.leaveUnresolved(nil)
    }
    await merge.ended()
    return merge
  }

  @Test func sameMergeFromOtherPathsOpensWithItsWork() async throws {
    let merge = try await leftMerge()
    let left = try merge.conflictSegments

    let restored = try await RestoredMerge(copying: merge)
    let controller = restored.controller

    #expect(try restored.conflictSegments == left)
    #expect(try restored.conflictSegments[2] == "edited: A 3 by hand\n")
    #expect(controller.comparisonOptions.mode == .ignoreWhitespaceAmount)
    let blocks = controller.presentation.changes.blocks
    #expect(controller.presentation.currentBlock == merge.conflicts[2])
    #expect(blocks[merge.conflicts[2]].kind == .conflict)
    await restored.close()
  }

  @Test func restoredWorkIsNamedInTheSubtitleAndToldToVoiceOver() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(copying: merge)
    let window = try #require(restored.controller.window)

    let note = RestoredWork(savedAt: WorkFolder.start, restartedBlockCount: 0).note(
      now: WorkFolder.start, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
    #expect(note.hasPrefix("Earlier work restored · "))
    #expect(window.subtitle.hasSuffix(note))
    #expect(window.accessibilityTitle()?.contains(note) == true)
    #expect(restored.announcements == ["Earlier work restored: 2 of 3 conflicts resolved."])
    await restored.close()
  }

  @Test func singleUndoTakesTheWindowBackToTheMergeAsLoaded() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(copying: merge)
    let undoManager = restored.undoManager

    #expect(undoManager.undoMenuItemTitle == "Undo Restore Earlier Work")
    undoManager.undo()
    restored.controller.endEvent()

    #expect(try restored.conflictSegments.allSatisfy { $0.hasPrefix("open") })
    #expect(restored.controller.presentation.result?.document.canResetAll == false)
    #expect(!undoManager.canUndo)
    #expect(undoManager.redoMenuItemTitle == "Redo Restore Earlier Work")
    #expect(restored.announcements.last == "Undo Restore Earlier Work. 3 Conflicts Left")
    await restored.close()
  }

  @Test func noteStaysWhileTheUserLooksAndGoesWithTheFirstStep() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(copying: merge)
    let controller = restored.controller
    let window = try #require(controller.window)
    #expect(window.subtitle.contains("Earlier work restored"))

    controller.perform(.nextChange)
    controller.endEvent()
    #expect(window.subtitle.contains("Earlier work restored"))

    controller.presentation.setCurrentBlock(merge.conflicts[1])
    controller.perform(.useB)
    controller.endEvent()
    #expect(!window.subtitle.contains("Earlier work"))
    await restored.close()
  }

  @Test func choiceOfTheLineEndingEndsTheNote() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(copying: merge)
    let window = try #require(restored.controller.window)
    #expect(window.subtitle.contains("Earlier work restored"))

    restored.controller.choose(.lineEnding(.crlf))

    #expect(!window.subtitle.contains("Earlier work"))
    await restored.close()
  }

  @Test func changedBaseOpensTheMergeAsLoaded() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(
      copying: merge, changing: [.base: WorkingMerge.base + "five\n"])
    let window = try #require(restored.controller.window)

    #expect(try restored.conflictSegments.allSatisfy { $0.hasPrefix("open") })
    #expect(restored.controller.comparisonOptions.mode == .windowDefault)
    #expect(!window.subtitle.contains("Earlier work"))
    #expect(!restored.undoManager.canUndo)
    #expect(restored.announcements.isEmpty)
    // The work of the merge before the change stays for when those files come again.
    #expect(try await merge.keptWork != nil)
    await restored.close()
  }

  @Test func mergeWithoutGitShowsTheDotOnceItDiffersFromTheFileItWasOpenedFrom() async throws {
    let merge = try await leftMerge(waitingCaller: nil)
    let restored = try await RestoredMerge(copying: merge, waitingCaller: nil)
    let window = try #require(restored.controller.window)

    #expect(window.isDocumentEdited)
    restored.undoManager.undo()
    restored.controller.endEvent()
    #expect(!window.isDocumentEdited)
    await restored.close()
  }

  @Test func workOfOtherBlocksIsPartlyRestoredAndSaysHowManyStartOver() async throws {
    let merge = try await leftMerge()
    let file = merge.work.url.appending(path: "\(MergeKey(merge.inputs).rawValue).json")
    // As from another version of the engine: other blocks, and conflict 0 no longer has the same
    // lines in A.
    var object = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    object["blocks"] = String(repeating: "0", count: 64)
    var segments = try #require(object["segments"] as? [[String: Any]])
    let decided = try #require(segments.firstIndex { $0["bytes"] != nil })
    var bytes = try #require(segments[decided]["bytes"] as? [[Int]])
    bytes[1][1] += 1
    segments[decided]["bytes"] = bytes
    object["segments"] = segments
    try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: file)

    let restored = try await RestoredMerge(copying: merge)
    let window = try #require(restored.controller.window)

    let segmentsShown = try restored.conflictSegments
    #expect(segmentsShown[0].hasPrefix("open"))
    #expect(segmentsShown[2] == "edited: A 3 by hand\n")
    #expect(window.subtitle.contains("Earlier work partly restored · "))
    #expect(restored.announcements == ["Earlier work partly restored: 1 block starts over."])
    await restored.close()
  }

  @Test func restoredWindowKeepsTheWorkItPutBackWhenClosed() async throws {
    let merge = try await leftMerge()
    let restored = try await RestoredMerge(copying: merge)
    let left = try restored.conflictSegments
    merge.work.now = WorkFolder.start.addingTimeInterval(60)

    await restored.close()

    let work = try #require(try await merge.keptWork)
    #expect(work.savedAt == WorkFolder.start.addingTimeInterval(60))
    let again = try await RestoredMerge(copying: merge)
    #expect(try again.conflictSegments == left)
    await again.close()
  }

  @Test(
    arguments: [
      (0, 0, "Earlier work restored · 06:13"),
      (-86_400 * 2, 0, "Earlier work restored · 7 May"),
      (-86_400 * 200, 3, "Earlier work partly restored · 21 Oct 2025"),
    ] as [(TimeInterval, Int, String)])
  func noteNamesTheTimeOfTodayAndTheDateOfOtherDays(
    age: TimeInterval, restarted: Int, expected: String
  ) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let work = RestoredWork(
      savedAt: WorkFolder.start.addingTimeInterval(age), restartedBlockCount: restarted)

    let note = work.note(
      now: WorkFolder.start, calendar: calendar, locale: Locale(identifier: "en_GB"))

    #expect(note == expected)
  }

  @Test func announcementOfAMergeWithoutConflictsNamesNoCount() {
    let work = RestoredWork(savedAt: WorkFolder.start, restartedBlockCount: 0)
    #expect(work.announcement(conflictCount: 0, openConflictCount: 0) == "Earlier work restored.")
    #expect(
      work.announcement(conflictCount: 1, openConflictCount: 0)
        == "Earlier work restored: 1 of 1 conflict resolved.")
  }
}
