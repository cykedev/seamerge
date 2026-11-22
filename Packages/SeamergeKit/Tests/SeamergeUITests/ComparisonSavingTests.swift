import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Saving the files of a comparison that copied changes, and every way their window closes or
/// loses them: what lands in the files, what the window asks, and what the caller hears.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ComparisonSavingTests {
  static let old = "one\ntwo\nthree\nfour\nfive\n"
  static let new = "one\n2\nthree\nfour\n5\n"

  /// A comparison of two files in a temporary folder, `left.txt` and `right.txt`, which the
  /// user chose, both of them writable; the folder is removed when the test ends.
  @MainActor
  final class Fixture {
    let folder: URL
    let prompts = PromptRecorder()
    let undoManager = UndoManager()
    let controller: SessionWindowController
    private(set) var outcomes: [String] = []

    init(
      old: Data = Data(ComparisonSavingTests.old.utf8),
      new: Data = Data(ComparisonSavingTests.new.utf8), mode: ComparisonMode = .windowDefault,
      context: SessionContext = SessionContext()
    ) async throws {
      folder = FileManager.default.temporaryDirectory.appending(
        path: "ComparisonSavingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try old.write(to: folder.appending(path: "left.txt"))
      try new.write(to: folder.appending(path: "right.txt"))
      let file = { [folder] (name: String) in
        SessionFile(url: folder.appending(path: name), label: name)
      }
      let session = try await Session.loadDiff(
        old: file("left.txt"), new: file("right.txt"), mode: mode)
      controller = try Windows.controller(
        for: session, context: context, prompts: prompts, undoManager: undoManager)
      controller.onFinish = { [weak self] outcome in
        self?.outcomes.append(outcome == .saved ? "saved" : "cancelled")
      }
    }

    isolated deinit {
      // A window that asked stands among the windows of the app, toolbar and all, until it
      // closes.
      controller.close()
      do {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record("Could not remove \(folder.path): \(error)")
      }
    }

    var left: URL { folder.appending(path: "left.txt") }
    var right: URL { folder.appending(path: "right.txt") }

    func bytes(of url: URL) throws -> Data {
      try Data(contentsOf: url)
    }

    /// The bytes that the window holds for the file of `role`.
    func shown(_ role: Role) -> Data? {
      controller.presentation.changes.session.inputs[role]?.bytes
    }

    /// Copies block `block` in `command`, which copies one change or all, and waits for it.
    func copy(_ command: SessionCommand, block: Int? = 0) async {
      if let block {
        controller.presentation.jump(to: block)
      }
      switch command {
      case .copyToRight: controller.copyToRight(nil)
      case .copyToLeft: controller.copyToLeft(nil)
      case .copyAllChangesToRight: controller.copyAllChangesToRight(nil)
      case .copyAllChangesToLeft: controller.copyAllChangesToLeft(nil)
      default: Issue.record("\(command) copies nothing")
      }
      await controller.copying?.value
    }

    var isEdited: Bool {
      controller.window?.isDocumentEdited == true
    }

    /// Whether the header of `role` says Edited, also to VoiceOver.
    func headerSaysEdited(_ role: Role) -> Bool {
      controller.presentation.headers[role]?.isEdited == true
        && controller.presentation.headers[role]?.spokenName.hasSuffix(", Edited") == true
    }
  }

  @Test func copyMarksTheTargetEditedAndSaveWritesItThenNothingIsEdited() async throws {
    let fixture = try await Fixture()
    let controller = fixture.controller
    #expect(!fixture.isEdited)
    #expect(!controller.canPerform(.save))
    #expect(!controller.canPerform(.saveAs))

    await fixture.copy(.copyToRight)

    #expect(fixture.isEdited)
    #expect(fixture.headerSaysEdited(.b))
    #expect(!fixture.headerSaysEdited(.a))
    #expect(controller.canPerform(.save))
    #expect(controller.canPerform(.saveAndClose))
    #expect(!controller.canPerform(.saveAs))
    #expect(Keys.of(.save, in: .diff) == Keys("s", .command))
    #expect(try fixture.bytes(of: fixture.right) == Data(Self.new.utf8))

    #expect(await controller.saveChangedFiles())

    #expect(try fixture.bytes(of: fixture.right) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(try fixture.bytes(of: fixture.left) == Data(Self.old.utf8))
    #expect(!fixture.isEdited)
    #expect(!fixture.headerSaysEdited(.b))
    #expect(!controller.canPerform(.save))
    #expect(fixture.prompts.questions.isEmpty)
  }

  @Test func undoPastTheSavedStateMakesTheFileEditedAgainAndRedoSavedAgain() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    #expect(await fixture.controller.saveChangedFiles())
    #expect(!fixture.isEdited)

    fixture.undoManager.undo()
    await fixture.controller.comparisonSwitcher.bringingBack?.value
    #expect(fixture.isEdited)
    #expect(fixture.headerSaysEdited(.b))
    #expect(fixture.shown(.b) == Data(Self.new.utf8))

    fixture.undoManager.redo()
    await fixture.controller.comparisonSwitcher.bringingBack?.value
    #expect(!fixture.isEdited)
  }

  @Test func undoOfAnUnsavedCopyLeavesNothingEdited() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    #expect(fixture.isEdited)

    fixture.undoManager.undo()
    await fixture.controller.comparisonSwitcher.bringingBack?.value

    #expect(!fixture.isEdited)
    #expect(!fixture.controller.canPerform(.save))
  }

  @Test func bothChangedFilesAreWritten() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight, block: 0)
    await fixture.copy(.copyToLeft, block: 0)
    #expect(fixture.headerSaysEdited(.a))
    #expect(fixture.headerSaysEdited(.b))

    #expect(await fixture.controller.saveAndCloseWindow())

    #expect(try fixture.bytes(of: fixture.right) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(try fixture.bytes(of: fixture.left) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func encodingByteOrderMarkLineEndingsAndPermissionsStayAsTheyWere() async throws {
    let old = "a\r\nb\r\nc\r\nd\r\n"
    let new = "a\r\nB\r\nc\r\nd\r\n"
    let encode = { (text: String) throws -> Data in
      try #require(text.data(using: .utf16LittleEndian)).withByteOrderMark
    }
    let fixture = try await Fixture(old: try encode(old), new: try encode(new))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o640], ofItemAtPath: fixture.right.path)

    await fixture.copy(.copyToRight)
    #expect(await fixture.controller.saveChangedFiles())

    #expect(try fixture.bytes(of: fixture.right) == encode(old))
    let permissions =
      try FileManager.default.attributesOfItem(atPath: fixture.right.path)[
        .posixPermissions] as? Int
    #expect(permissions == 0o640)
  }

  @Test func onlyTheCopiedLinesChangeInAFileWithMixedLineEndings() async throws {
    let old = "a\r\nb\nc\r\nd\n"
    let new = "a\r\nB\nc\r\nD\n"
    let fixture = try await Fixture(old: Data(old.utf8), new: Data(new.utf8))

    await fixture.copy(.copyToRight, block: 0)
    #expect(await fixture.controller.saveChangedFiles())

    #expect(try fixture.bytes(of: fixture.right) == Data("a\r\nb\nc\r\nD\n".utf8))
  }

  @Test func symbolicLinkIsWrittenThroughAndStays() async throws {
    let fixture = try await Fixture()
    let target = fixture.folder.appending(path: "target.txt")
    try FileManager.default.moveItem(at: fixture.right, to: target)
    try FileManager.default.createSymbolicLink(at: fixture.right, withDestinationURL: target)

    await fixture.copy(.copyToRight)
    #expect(await fixture.controller.saveChangedFiles())

    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: fixture.right.path)
        == target.path)
    #expect(try fixture.bytes(of: target) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
  }

  @Test func closingAsksAndSaveWritesThenReportsSaved() async throws {
    let fixture = try await Fixture()
    fixture.prompts.unsavedChangesChoice = .save
    await fixture.copy(.copyToRight)

    #expect(await fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions == ["save changes to right.txt"])
    #expect(try fixture.bytes(of: fixture.right) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func dontSaveLeavesTheFileAsItWasAndReportsSaved() async throws {
    let fixture = try await Fixture()
    fixture.prompts.unsavedChangesChoice = .discard
    await fixture.copy(.copyToRight)

    #expect(await fixture.controller.closeAskingFirst())

    #expect(try fixture.bytes(of: fixture.right) == Data(Self.new.utf8))
    #expect(fixture.outcomes == ["saved"])
    #expect(fixture.controller.window?.isVisible != true)
  }

  @Test func cancelKeepsTheWindowAndItsChanges() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let window = try #require(fixture.controller.window)
    window.makeKeyAndOrderFront(nil)

    #expect(!fixture.controller.windowShouldClose(window))
    await Task.yield()
    #expect(!(await fixture.controller.closeAskingFirst()))

    #expect(fixture.prompts.questions.last == "save changes to right.txt")
    #expect(window.isVisible)
    #expect(fixture.outcomes.isEmpty)
    #expect(fixture.isEdited)
    window.close()
  }

  @Test func closingWithoutChangesAsksNothing() async throws {
    let fixture = try await Fixture()

    #expect(await fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions.isEmpty)
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func quittingAsksAndReportsCancelledSoThatGitComparesNoFurtherFiles() async throws {
    let fixture = try await Fixture()
    fixture.prompts.unsavedChangesChoice = .save
    await fixture.copy(.copyToRight)
    #expect(fixture.controller.hasUnsavedChanges)

    #expect(await fixture.controller.closeAskingFirst(asTheAppQuits: true))

    #expect(fixture.prompts.questions == ["save changes to right.txt"])
    #expect(try fixture.bytes(of: fixture.right) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(fixture.outcomes == ["cancelled"])
  }

  @Test func failureToWriteKeepsTheFileTheWindowAndItsChanges() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: fixture.folder.path)

    #expect(!(await fixture.controller.saveAndCloseWindow()))

    #expect(fixture.prompts.questions == ["failed saving right.txt"])
    #expect(try fixture.bytes(of: fixture.right) == Data(Self.new.utf8))
    #expect(fixture.isEdited)
    #expect(fixture.outcomes.isEmpty)
    fixture.controller.window?.close()
  }

  @Test func textTheEncodingCannotHoldIsCopiedInUTF8AndSavingOffersUTF8First() async throws {
    let target = try #require("\u{201C}a\u{201D}\nold\n".data(using: .windowsCP1252))
    let fixture = try await Fixture(
      old: Data("\u{201C}a\u{201D}\n\u{2713} done\n".utf8), new: target)

    await fixture.copy(.copyToRight)

    #expect(fixture.shown(.b) == Data("\u{201C}a\u{201D}\n\u{2713} done\n".utf8))
    #expect(fixture.controller.presentation.changes.session.inputs.b.encoding == .utf8)
    #expect(fixture.controller.presentation.changes.blocks.isEmpty)
    #expect(!(await fixture.controller.saveChangedFiles()))
    #expect(fixture.prompts.questions == ["save right.txt as UTF-8 instead of Windows 1252"])
    #expect(try fixture.bytes(of: fixture.right) == target)
    #expect(fixture.isEdited)

    fixture.prompts.savesAsUTF8 = true
    #expect(await fixture.controller.saveChangedFiles())
    #expect(
      try fixture.bytes(of: fixture.right) == Data("\u{201C}a\u{201D}\n\u{2713} done\n".utf8))
    #expect(!fixture.isEdited)

    fixture.undoManager.undo()
    await fixture.controller.comparisonSwitcher.bringingBack?.value
    #expect(fixture.controller.presentation.changes.session.inputs.b.encoding == .windows1252)
    #expect(fixture.isEdited)
  }

  @Test func skippingTheRemainingFilesAsksThenReportsCancelled() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)

    #expect(!(await fixture.controller.skipRemainingFilesAskingFirst()))
    #expect(fixture.outcomes.isEmpty)

    fixture.prompts.unsavedChangesChoice = .discard
    #expect(await fixture.controller.skipRemainingFilesAskingFirst())
    #expect(fixture.prompts.questions == Array(repeating: "save changes to right.txt", count: 2))
    #expect(try fixture.bytes(of: fixture.right) == Data(Self.new.utf8))
    #expect(fixture.outcomes == ["cancelled"])
  }

  @Test func fileChangedOnDiskWithoutOwnChangesReloadsWithoutAsking() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let other = "zero\n" + Self.old
    try Data(other.utf8).write(to: fixture.left)

    await fixture.controller.diskWatch.reloadChangedFiles()

    #expect(fixture.prompts.questions.isEmpty)
    #expect(fixture.shown(.a) == Data(other.utf8))
    #expect(fixture.headerSaysEdited(.b))
    #expect(!fixture.headerSaysEdited(.a))
  }

  @Test func fileChangedOnDiskWithOwnChangesAsksAndKeepingItSavesOverTheChange() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let copied = try #require(fixture.shown(.b))
    try Data("written by another app\n".utf8).write(to: fixture.right)

    await fixture.controller.diskWatch.reloadChangedFiles()

    #expect(fixture.prompts.questions == ["reload changed right.txt"])
    #expect(fixture.shown(.b) == copied)
    #expect(fixture.isEdited)
    #expect(await fixture.controller.saveChangedFiles())
    #expect(try fixture.bytes(of: fixture.right) == copied)
    #expect(fixture.prompts.questions == ["reload changed right.txt"])
  }

  @Test func fileChangedOnDiskWithOwnChangesReloadsAsAStepOfUndo() async throws {
    let fixture = try await Fixture()
    fixture.prompts.reloadsChangedResult = true
    await fixture.copy(.copyToRight)
    let copied = try #require(fixture.shown(.b))
    let other = Data("written by another app\n".utf8)
    try other.write(to: fixture.right)

    await fixture.controller.diskWatch.reloadChangedFiles()

    #expect(fixture.prompts.questions == ["reload changed right.txt"])
    #expect(fixture.shown(.b) == other)
    #expect(!fixture.isEdited)
    #expect(fixture.undoManager.undoActionName == SessionWindowController.reloadName)

    fixture.undoManager.undo()
    await fixture.controller.comparisonSwitcher.bringingBack?.value
    #expect(fixture.shown(.b) == copied)
    #expect(fixture.isEdited)
  }

  @Test func changeByAnotherAppSinceTheCopyIsAskedAboutBeforeSaving() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let copied = try #require(fixture.shown(.b))
    try Data("written by another app\n".utf8).write(to: fixture.right)

    #expect(await fixture.controller.saveChangedFiles())
    #expect(fixture.prompts.questions == ["reload changed right.txt"])
    #expect(try fixture.bytes(of: fixture.right) == copied)

    await fixture.copy(.copyToRight)
    let reloaded = Data("written again\n".utf8)
    try reloaded.write(to: fixture.right)
    fixture.prompts.reloadsChangedResult = true
    #expect(!(await fixture.controller.saveChangedFiles()))
    #expect(try fixture.bytes(of: fixture.right) == reloaded)
    #expect(fixture.shown(.b) == reloaded)
  }

  @Test func ownSavingIsNoChangeByAnotherApp() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    #expect(await fixture.controller.saveChangedFiles())

    await fixture.controller.diskWatch.reloadChangedFiles()

    #expect(fixture.prompts.questions.isEmpty)
    #expect(!fixture.isEdited)
  }

  @Test func changingTheFilesAsksAboutTheCopiedChangesFirst() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let other = fixture.folder.appending(path: "other.txt")
    try Data("other\n".utf8).write(to: other)
    let comparison = FileComparison(left: fixture.left, base: nil, right: other)

    try await fixture.controller.changeFiles(to: comparison)
    #expect(fixture.prompts.questions == ["save changes to right.txt"])
    #expect(fixture.controller.presentation.changes.session.inputs.b.url == fixture.right)
    #expect(fixture.isEdited)

    fixture.prompts.unsavedChangesChoice = .save
    try await fixture.controller.changeFiles(to: comparison)
    #expect(fixture.controller.presentation.changes.session.inputs.b.url == other)
    #expect(try fixture.bytes(of: fixture.right) == Data("one\ntwo\nthree\nfour\n5\n".utf8))
    #expect(!fixture.isEdited)
  }

  @Test func switchingTheComparisonModeKeepsTheCopiedChanges() async throws {
    let fixture = try await Fixture()
    await fixture.copy(.copyToRight)
    let copied = try #require(fixture.shown(.b))

    var options = fixture.controller.comparisonOptions
    options.mode = .exact
    await fixture.controller.switchComparison(to: options)

    #expect(fixture.shown(.b) == copied)
    #expect(fixture.isEdited)
  }
}

extension Data {
  /// The UTF-16 little-endian bytes with the byte order mark before them.
  fileprivate var withByteOrderMark: Data {
    Data([0xFF, 0xFE]) + self
  }
}
