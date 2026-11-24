import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// A result file that another app changed and the window reloaded: whether closing asks, and how
/// the session ends for the command that waits for it.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ReloadedResultTests {
  static let base = "one\ntwo\nthree\n"
  static let a = "one\ntwo from A\nthree\n"
  static let b = "one\ntwo from B\nthree\n"
  static let external = "one\nwritten elsewhere\nthree\n"

  /// A merge of files in a temporary folder with one conflict, which the window decides for B
  /// if asked to.
  @MainActor
  private final class Fixture {
    let folder: URL
    let prompts = PromptRecorder()
    let undoManager = UndoManager()
    let controller: SessionWindowController
    private(set) var outcomes: [SessionOutcome] = []

    /// A merge whose result goes to `result.txt`, which Git or a command line waits for as
    /// `waitingCaller` says, or with no result file, as one from Compare Files, for `nil`.
    init(waitingCaller: WaitingCaller?, hasResultFile: Bool = true, decides: Bool = true)
      async throws
    {
      let folder = FileManager.default.temporaryDirectory.appending(
        path: "ReloadedResultTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      self.folder = folder
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for (name, text) in [("base.txt", base), ("a.txt", a), ("b.txt", b)] {
        try Data(text.utf8).write(to: folder.appending(path: name))
      }
      let file = { (name: String) in SessionFile(url: folder.appending(path: name), label: name) }
      let session = try await Session.loadMerge(
        base: file("base.txt"), a: file("a.txt"), b: file("b.txt"), mode: .windowDefault)
      let resultURL = hasResultFile ? folder.appending(path: "result.txt") : nil
      if let resultURL {
        try Data("<<<<<<< conflict\n".utf8).write(to: resultURL)
      }
      controller = try Windows.controller(
        for: session, context: SessionContext(resultURL: resultURL, waitingCaller: waitingCaller),
        prompts: prompts, undoManager: undoManager)
      controller.onFinish = { [unowned self] in outcomes.append($0) }
      if decides {
        controller.presentation.setCurrentBlock(
          controller.presentation.navigation.firstOpenConflict)
        controller.perform(.useB)
        controller.endEvent()
      }
    }

    isolated deinit {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record("Could not remove \(folder.path): \(error)")
      }
    }

    var resultURL: URL { folder.appending(path: "result.txt") }

    var isEdited: Bool { controller.window?.isDocumentEdited == true }

    var openConflictCount: Int? { controller.presentation.result?.document.openConflictCount }

    /// Has another app write `text` to the file at `url`, and the window look at it, answering
    /// the sheet with Reload or, with `reloads` off, Keep My Version.
    func changeOnDisk(
      _ text: String = ReloadedResultTests.external, at url: URL? = nil, reloads: Bool = true
    ) async throws {
      try Data(text.utf8).write(to: url ?? resultURL, options: .atomic)
      prompts.reloadsChangedResult = reloads
      await controller.diskWatch.reloadChangedFiles()
      controller.endEvent()
    }

    func undo() async {
      undoManager.undo()
      await controller.comparisonSwitcher.bringingBack?.value
      controller.endEvent()
    }

    func redo() async {
      undoManager.redo()
      await controller.comparisonSwitcher.bringingBack?.value
      controller.endEvent()
    }

    /// The bytes the window writes for what it shows now.
    var exportedText: String? {
      controller.presentation.result.map {
        $0.document.exportText(of: $0.text, labels: controller.conflictLabels)
      }
    }

    func resultFileText() throws -> String {
      String(decoding: try Data(contentsOf: resultURL), as: UTF8.self)
    }
  }

  @Test(arguments: [WaitingCaller.git, .commandLine])
  func reloadLeavesAMergeThatACommandWaitsForUnsavedSoDontSaveReportsCancelled(
    caller: WaitingCaller
  ) async throws {
    let fixture = try await Fixture(waitingCaller: caller)
    try await fixture.changeOnDisk()
    #expect(fixture.controller.presentation.result?.text == Self.external)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.closeAskingFirst())

    let callerName = caller == .git ? "Git" : "command line"
    #expect(fixture.prompts.questions.last == "close result.txt, 0 open, \(callerName)")
    #expect(fixture.outcomes == [.cancelled])
    #expect(try fixture.resultFileText() == Self.external)
  }

  @Test func savingAfterReloadWritesTheReloadedTextAndReportsSaved() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    try await fixture.changeOnDisk()
    // Reloading takes the file's text as typed, which resolves every open conflict.
    #expect(fixture.openConflictCount == 0)

    fixture.prompts.unsavedChangesChoice = .save
    #expect(await fixture.controller.closeAskingFirst())

    #expect(
      fixture.prompts.questions == ["reload changed result.txt", "close result.txt, 0 open, Git"])
    #expect(fixture.outcomes == [.saved])
    #expect(try fixture.resultFileText() == Self.external)
  }

  @Test func undoOfAReloadBringsBackOpenConflictsThatSavingWritesAsMarkers() async throws {
    let fixture = try await Fixture(waitingCaller: .git, decides: false)
    try await fixture.changeOnDisk()
    await fixture.undo()
    #expect(fixture.openConflictCount == 1)
    #expect(fixture.isEdited)
    let expected = try #require(fixture.exportedText)

    fixture.prompts.unsavedChangesChoice = .save
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    #expect(await fixture.controller.closeAskingFirst())

    #expect(
      Array(fixture.prompts.questions.suffix(2)) == [
        "close result.txt, 1 open, Git", "save with 1 open conflicts, Git",
      ])
    #expect(fixture.outcomes == [.saved])
    #expect(try fixture.resultFileText() == expected)
    #expect(expected.contains("<<<<<<< "))
  }

  @Test func reloadAfterSavingLeavesTheMergeUnsavedAgainAndSoDoUndoAndRedo() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    #expect(await fixture.controller.save())
    #expect(!fixture.isEdited)

    try await fixture.changeOnDisk()
    #expect(fixture.isEdited)
    // Undo shows what was saved, but the file holds what the other app wrote.
    await fixture.undo()
    #expect(fixture.isEdited)
    await fixture.redo()
    #expect(fixture.controller.presentation.result?.text == Self.external)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions.last == "close result.txt, 0 open, Git")
    #expect(fixture.outcomes == [.cancelled])
  }

  @Test func reloadAfterSavingThenSavingAgainReportsSaved() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    #expect(await fixture.controller.save())
    try await fixture.changeOnDisk()

    #expect(await fixture.controller.saveAndCloseWindow())

    #expect(fixture.outcomes == [.saved])
    #expect(try fixture.resultFileText() == Self.external)
  }

  @Test func reloadAskedAboutWhileSavingLeavesTheMergeUnsavedAndOpen() async throws {
    let fixture = try await Fixture(waitingCaller: .git, decides: false)
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    fixture.prompts.reloadsChangedResult = true
    fixture.prompts.whileAskingToSaveWithOpenConflicts = {
      do {
        try Data(Self.external.utf8).write(to: fixture.resultURL, options: .atomic)
      } catch {
        Issue.record(error)
      }
    }

    #expect(await !fixture.controller.saveAndCloseWindow())
    #expect(fixture.controller.presentation.result?.text == Self.external)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions.last == "close result.txt, 0 open, Git")
    #expect(fixture.outcomes == [.cancelled])
  }

  @Test func leavingAReloadedMergeUnresolvedReportsCancelled() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    try await fixture.changeOnDisk()

    fixture.controller.leaveUnresolved(nil)

    #expect(fixture.outcomes == [.cancelled])
    #expect(try fixture.resultFileText() == Self.external)
  }

  @Test func keepingMyVersionInAMergeThatGitWaitsForStillAsksBeforeClosing() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    #expect(await fixture.controller.save())
    try await fixture.changeOnDisk(reloads: false)
    #expect(fixture.controller.presentation.result?.text == Self.b)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions.last == "close result.txt, 0 open, Git")
    #expect(fixture.outcomes == [.cancelled])
  }

  @Test func reloadInAMergeFromCompareFilesMatchesTheFileSoClosingAsksNothing() async throws {
    let fixture = try await Fixture(waitingCaller: nil, hasResultFile: false)
    let destination = fixture.folder.appending(path: "merged.txt")
    fixture.prompts.destination = destination
    #expect(await fixture.controller.save())

    try await fixture.changeOnDisk(at: destination)
    #expect(fixture.controller.presentation.result?.text == Self.external)
    #expect(!fixture.isEdited)

    let questionCount = fixture.prompts.questions.count
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions.count == questionCount)
  }

  @Test func sourceReloadedOnItsOwnAfterSavingLeavesTheMergeUnsaved() async throws {
    let fixture = try await Fixture(waitingCaller: .git)
    #expect(await fixture.controller.save())

    try await fixture.changeOnDisk("zero\n" + Self.a, at: fixture.folder.appending(path: "a.txt"))
    #expect(fixture.controller.presentation.changes.session.inputs[.a]?.text == "zero\n" + Self.a)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.outcomes == [.cancelled])
  }
}
