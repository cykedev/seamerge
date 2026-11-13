import AppKit
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// Files that change on disk while their window is open, and other files chosen for a window.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct DiskChangeTests {
  static let base = "one\ntwo\nthree\nfour\nfive\n"
  static let a = "one\ntwo from A\nthree\nfour\nfive\n"
  static let b = "one\ntwo from B\nthree\nfour\nfive from B\n"

  /// A merge of files in a temporary folder, whose window has decided the conflict for B.
  @MainActor
  private final class Fixture {
    let folder: URL
    let prompts = PromptRecorder()
    let undoManager = UndoManager()
    private(set) var controller: SessionWindowController

    init(resultFile: Bool = false, waitingCaller: WaitingCaller? = nil) async throws {
      let folder = FileManager.default.temporaryDirectory.appending(
        path: "DiskChangeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      self.folder = folder
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for (name, text) in [("base.txt", base), ("a.txt", a), ("b.txt", b)] {
        try Data(text.utf8).write(to: folder.appending(path: name))
      }
      let file = { (name: String) in SessionFile(url: folder.appending(path: name), label: name) }
      let session = try await Session.loadMerge(
        base: file("base.txt"), a: file("a.txt"), b: file("b.txt"))
      let resultURL = resultFile ? folder.appending(path: "result.txt") : nil
      if let resultURL {
        try Data("<<<<<<< conflict\n".utf8).write(to: resultURL)
      }
      controller = try Windows.controller(
        for: session, context: SessionContext(resultURL: resultURL, waitingCaller: waitingCaller),
        prompts: prompts,
        undoManager: undoManager)
      controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
      controller.perform(.useB)
      controller.endEvent()
    }

    isolated deinit {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record("Could not remove \(folder.path): \(error)")
      }
    }

    func url(_ name: String) -> URL { folder.appending(path: name) }

    func text(of role: Role) -> String? {
      controller.presentation.changes.session.file(for: role)?.text
    }

    var conflict: Block? {
      controller.presentation.changes.blocks.first { $0.kind == .conflict }
    }

    var conflictState: Segment.State? {
      conflict.flatMap { controller.presentation.result?.document.segment(for: $0).state }
    }
  }

  @Test func sourceWrittenInPlaceIsReloadedWithItsDecisionsAndUndoBringsBackTheOldOne()
    async throws
  {
    let fixture = try await Fixture()
    let changed = "zero\n" + Self.a
    try Data(changed.utf8).write(to: fixture.url("a.txt"))

    await fixture.controller.reloadChangedFiles()

    #expect(fixture.text(of: .a) == changed)
    #expect(fixture.conflictState == .chosen)
    #expect(fixture.prompts.questions.isEmpty)
    fixture.controller.endEvent()
    fixture.undoManager.undo()
    #expect(fixture.text(of: .a) == Self.a)
    #expect(fixture.conflictState == .chosen)
  }

  @Test func sourceReplacedAtomicallyThatLosesADecisionAsksFirstAndOnlyOnce() async throws {
    let fixture = try await Fixture()
    let changed = Self.a.replacingOccurrences(of: "two from A", with: "two, now from A")
    try Data(changed.utf8).write(to: fixture.url("a.txt"), options: .atomic)

    await fixture.controller.reloadChangedFiles()
    await fixture.controller.reloadChangedFiles()

    #expect(fixture.prompts.questions == ["reload a.txt, 1 decisions"])
    #expect(fixture.text(of: .a) == Self.a)
    #expect(fixture.conflictState == .chosen)

    fixture.prompts.reloadsAnyway = true
    let again = changed + "six\n"
    try Data(again.utf8).write(to: fixture.url("a.txt"), options: .atomic)
    await fixture.controller.reloadChangedFiles()
    #expect(fixture.text(of: .a) == again)
    #expect(fixture.conflictState == .open)
  }

  @Test func deletedSourceLeavesTheWindowAsItIs() async throws {
    let fixture = try await Fixture()
    try FileManager.default.removeItem(at: fixture.url("a.txt"))

    await fixture.controller.reloadChangedFiles()

    #expect(fixture.text(of: .a) == Self.a)
    #expect(fixture.conflictState == .chosen)
    #expect(fixture.prompts.questions.isEmpty)
  }

  @Test func resultChangedByAnotherAppAsksOnceAndKeepsTheWindowsVersion() async throws {
    let fixture = try await Fixture(resultFile: true)
    let text = fixture.controller.presentation.result?.text
    try Data("edited elsewhere\n".utf8).write(to: fixture.url("result.txt"))

    await fixture.controller.reloadChangedFiles()
    await fixture.controller.reloadChangedFiles()

    #expect(fixture.prompts.questions == ["reload changed result.txt"])
    #expect(fixture.controller.presentation.result?.text == text)
  }

  @Test func reloadingTheChangedResultTakesItsTextAsSavedAndUndoMakesItUnsavedAgain()
    async throws
  {
    let fixture = try await Fixture(resultFile: true)
    fixture.prompts.reloadsChangedResult = true
    let text = fixture.controller.presentation.result?.text
    try Data("edited elsewhere\n".utf8).write(to: fixture.url("result.txt"), options: .atomic)

    await fixture.controller.reloadChangedFiles()

    #expect(fixture.controller.presentation.result?.text == "edited elsewhere\n")
    #expect(fixture.controller.window?.isDocumentEdited == false)
    fixture.controller.endEvent()
    fixture.undoManager.undo()
    #expect(fixture.controller.presentation.result?.text == text)
    #expect(fixture.controller.window?.isDocumentEdited == true)
    fixture.undoManager.redo()
    #expect(fixture.controller.window?.isDocumentEdited == false)
  }

  @Test func keepingMyVersionLeavesTheWindowUnsavedSoThatClosingAsksAndDoneWrites() async throws {
    let fixture = try await Fixture(resultFile: true)
    let controller = fixture.controller
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    #expect(await controller.save())
    #expect(controller.window?.isDocumentEdited == false)
    try Data("edited elsewhere\n".utf8).write(to: fixture.url("result.txt"))
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }

    await controller.reloadChangedFiles()

    #expect(controller.window?.isDocumentEdited == true)
    #expect(await !controller.closeAskingFirst())
    #expect(fixture.prompts.questions.last == "close result.txt, 0 open")
    #expect(await controller.saveAndCloseWindow())
    #expect(try Data(contentsOf: fixture.url("result.txt")) != Data("edited elsewhere\n".utf8))
    #expect(outcomes.count == 1 && { if case .saved = outcomes[0] { true } else { false } }())
  }

  @Test func undoOfAReloadStaysWhenNothingChangesOnDiskAgain() async throws {
    let fixture = try await Fixture()
    let changed = "zero\n" + Self.a
    try Data(changed.utf8).write(to: fixture.url("a.txt"))
    await fixture.controller.reloadChangedFiles()
    fixture.controller.endEvent()

    fixture.undoManager.undo()
    await fixture.controller.reloadChangedFiles()

    #expect(fixture.text(of: .a) == Self.a)
    #expect(fixture.undoManager.canRedo)
    fixture.undoManager.redo()
    #expect(fixture.text(of: .a) == changed)
  }

  @Test func changeOnDiskWhileSavingIsReloadedOnlyAfterwards() async throws {
    let fixture = try await Fixture()
    let controller = fixture.controller
    let destination = fixture.url("merged.txt")
    fixture.prompts.destination = destination
    let shown = try #require(controller.presentation.result)
    let expected = shown.document.exportText(of: shown.text, labels: controller.conflictLabels)
    fixture.prompts.whileAskingWhereToSave = {
      do {
        try Data(("zero\n" + Self.a).utf8).write(to: fixture.url("a.txt"))
      } catch {
        Issue.record(error)
      }
      await controller.reloadChangedFiles()
    }

    #expect(await controller.save())

    #expect(try Data(contentsOf: destination) == Data(expected.utf8))
    #expect(controller.window?.isDocumentEdited == false)
    #expect(fixture.text(of: .a) == Self.a)
    await controller.reloadChangedFiles()
    #expect(fixture.text(of: .a) == "zero\n" + Self.a)
    #expect(controller.fileWatchers.map(\.url).contains(destination))
  }

  @Test func ownSavingIsNoChangeByAnotherApp() async throws {
    let fixture = try await Fixture(resultFile: true)
    fixture.prompts.openConflictsChoice = .saveWithMarkers
    #expect(await fixture.controller.save())

    await fixture.controller.reloadChangedFiles()

    #expect(fixture.prompts.questions.isEmpty)
  }

  @Test func otherFilesTakeThePlaceOfTheShownOnesAfterAskingAboutLostDecisions() async throws {
    let fixture = try await Fixture()
    let controller = fixture.controller
    let swapped = FileComparison(
      left: fixture.url("b.txt"), base: fixture.url("base.txt"), right: fixture.url("a.txt"))

    try await controller.changeFiles(to: swapped)
    #expect(fixture.prompts.questions == ["change files, 1 decisions"])
    #expect(fixture.text(of: .a) == Self.a)

    fixture.prompts.changesAnyway = true
    try await controller.changeFiles(to: swapped)
    #expect(fixture.text(of: .a) == Self.b)
    #expect(fixture.text(of: .b) == Self.a)
    #expect(controller.presentation.headers[.a]?.name == "b.txt")
    #expect(fixture.conflictState == .open)
    controller.endEvent()
    fixture.undoManager.undo()
    #expect(fixture.text(of: .a) == Self.a)
    #expect(controller.presentation.headers[.a]?.name == "a.txt")
  }

  @Test func filesThatCannotBeComparedChangeNothing() async throws {
    let fixture = try await Fixture()
    try Data([0, 1, 2]).write(to: fixture.url("binary.bin"))
    let comparison = FileComparison(
      left: fixture.url("binary.bin"), base: fixture.url("base.txt"), right: fixture.url("b.txt"))

    await #expect(throws: SessionLoadingError.binaryFile(fixture.url("binary.bin"))) {
      try await fixture.controller.changeFiles(to: comparison)
    }
    #expect(fixture.text(of: .a) == Self.a)
  }

  @Test func sheetOfChangeFilesOpensWithTheFilesInTheirRolesAndCancelChangesNothing()
    async throws
  {
    let fixture = try await Fixture()
    let controller = fixture.controller
    #expect(controller.canPerform(.changeFiles))

    controller.changeFiles(nil)

    let sheet = try #require(controller.changeFilesSheet)
    #expect(
      sheet.selection.comparison
        == FileComparison(
          left: fixture.url("a.txt"), base: fixture.url("base.txt"), right: fixture.url("b.txt")))
    #expect(sheet.openButton.title == "Change")
    #expect(sheet.openButton.isEnabled)
    sheet.clear(.base)
    #expect(!sheet.openButton.isEnabled)
    sheet.cancelOperation(nil)
    #expect(controller.window?.attachedSheet == nil)
    #expect(fixture.text(of: .a) == Self.a)
  }

  @Test func filesOfASessionThatGitStartedCannotBeChanged() async throws {
    let fixture = try await Fixture(resultFile: true, waitingCaller: .git)

    #expect(!fixture.controller.canPerform(.changeFiles))
  }

  @Test func watcherTellsOfWritingReplacingRemovingAndPuttingBack() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "FileWatcher-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "watched.txt")
    try Data("one\n".utf8).write(to: url)
    let (events, continuation) = AsyncStream.makeStream(of: Void.self)
    let watcher = FileWatcher(url: url) { continuation.yield() }
    var iterator = events.makeAsyncIterator()

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("two\n".utf8))
    try handle.close()
    #expect(await iterator.next() != nil)
    try Data("replaced\n".utf8).write(to: url, options: .atomic)
    #expect(await iterator.next() != nil)
    try FileManager.default.removeItem(at: url)
    #expect(await iterator.next() != nil)
    try Data("back\n".utf8).write(to: url)
    #expect(await iterator.next() != nil)
    withExtendedLifetime(watcher) {}
  }

  /// A watcher follows a file to its replacement and tells of writing to it in place.
  ///
  /// Writing in place changes nothing in the folder, so only a watcher of the new file tells.
  /// Each round waits for a
  /// change that shows the line written last, which a late report of the replacement may
  /// show at most for the first rounds.
  @Test func watcherFollowsAReplacedFileAndTellsOfWritingInPlace() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "FileWatcher-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "watched.txt")
    try Data("one\n".utf8).write(to: url)
    let (contents, continuation) = AsyncStream.makeStream(of: String.self)
    let watcher = FileWatcher(url: url) {
      continuation.yield(
        String(decoding: FileManager.default.contents(atPath: url.path) ?? Data(), as: UTF8.self))
    }
    var iterator = contents.makeAsyncIterator()
    try Data("replaced\n".utf8).write(to: url, options: .atomic)
    #expect(await iterator.next() != nil)

    for round in 1...6 {
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: Data("line \(round)\n".utf8))
      try handle.close()
      while let content = await iterator.next(), !content.contains("line \(round)\n") {}
    }
    withExtendedLifetime(watcher) {}
  }
}
