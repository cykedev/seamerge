import AppKit
import FolderCompareTestSupport
import MergeModel
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// Copied changes in a window of several files: they survive going to another file, the list
/// marks them, Save writes every file, and closing asks once for all of them.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CollectionSavingTests {
  /// A window that compares two folders the user chose, with a project in them.
  @MainActor
  final class Fixture {
    let folders: SampleFolders
    let collection: FileCollection
    let prompts = PromptRecorder()
    let controller: SessionWindowController
    private(set) var outcomes: [String] = []

    init(waitsForEveryFile: Bool = false) async throws {
      folders = try SampleFolders()
      try folders.fillWithProject()
      collection = await FileCollection.compared(folders)
      controller = try await Windows.controller(for: collection, prompts: prompts)
      if waitsForEveryFile {
        // Every file shows its headers above empty panes before its lines.
        controller.fileWait = 0
      }
      controller.onFinish = { [weak self] outcome in
        self?.outcomes.append(outcome == .saved ? "saved" : "cancelled")
      }
    }

    isolated deinit {
      // A window that asked stands among the windows of the app, toolbar and all, until it
      // closes.
      controller.close()
    }

    /// Shows the file at `path` of the collection and waits until it shows its lines.
    func show(_ path: String) async throws {
      let index = try #require(collection.files.firstIndex { $0.path == path })
      controller.showFile(at: index)
      await controller.fileLoad?.value
      #expect(controller.collectionNavigator?.shownFile?.path == path)
    }

    /// Copies every change of the file in view to the right and waits for it.
    func copyAllToRight() async {
      controller.copyAllChangesToRight(nil)
      await controller.copying?.value
    }

    func right(_ path: String) throws -> Data {
      try Data(contentsOf: folders.right.appending(path: path))
    }

    func left(_ path: String) throws -> Data {
      try Data(contentsOf: folders.left.appending(path: path))
    }

    var markedPaths: Set<String> {
      controller.collectionLayout?.fileList.changedPaths ?? []
    }

    var shownRight: Data? {
      controller.presentation.changes.session.inputs.b.bytes
    }
  }

  @Test(arguments: [false, true])
  func changesSurviveGoingToAnotherFileAndBack(waitsForEveryFile: Bool) async throws {
    let fixture = try await Fixture(waitsForEveryFile: waitsForEveryFile)
    let readme = try fixture.right("README.md")
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    let copied = try #require(fixture.shownRight)
    #expect(fixture.markedPaths == ["README.md"])

    try await fixture.show("VERSION")
    #expect(fixture.markedPaths == ["README.md"])
    #expect(fixture.controller.window?.isDocumentEdited == true)
    #expect(fixture.controller.canPerform(.save))
    #expect(fixture.controller.presentation.headers[.b]?.isEdited == false)

    try await fixture.show("README.md")
    #expect(fixture.shownRight == copied)
    #expect(fixture.controller.presentation.headers[.b]?.isEdited == true)
    #expect(fixture.controller.presentation.changes.blocks.isEmpty)
    #expect(try fixture.right("README.md") == readme)
    #expect(fixture.markedPaths == ["README.md"])
  }

  @Test func saveWritesEveryChangedFileAndTheDotsGo() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    await fixture.copyAllToRight()
    #expect(fixture.markedPaths == ["README.md", "VERSION"])

    #expect(await fixture.controller.saveChangedFiles())

    #expect(try fixture.right("README.md") == fixture.left("README.md"))
    #expect(try fixture.right("VERSION") == fixture.left("VERSION"))
    #expect(fixture.markedPaths.isEmpty)
    #expect(fixture.controller.window?.isDocumentEdited == false)
    #expect(!fixture.controller.canPerform(.save))
    #expect(fixture.prompts.questions.isEmpty)

    try await fixture.show("README.md")
    #expect(fixture.controller.presentation.changes.blocks.isEmpty)
    #expect(fixture.controller.presentation.headers[.b]?.isEdited == false)
  }

  @Test func closingAsksOnceForEveryChangedFile() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    await fixture.copyAllToRight()
    fixture.prompts.unsavedChangesChoice = .save

    #expect(await fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions == ["save changes to VERSION, README.md"])
    #expect(try fixture.right("README.md") == fixture.left("README.md"))
    #expect(try fixture.right("VERSION") == fixture.left("VERSION"))
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func dontSaveLeavesEveryFileAsItWas() async throws {
    let fixture = try await Fixture()
    let readme = try fixture.right("README.md")
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    fixture.prompts.unsavedChangesChoice = .discard

    #expect(await fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions == ["save changes to README.md"])
    #expect(try fixture.right("README.md") == readme)
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func changesOfAFileAwayAreComparedAnewInTheModeOfTheWindow() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    let copied = try #require(fixture.shownRight)
    try await fixture.show("VERSION")

    var options = fixture.controller.comparisonOptions
    options.mode = .exact
    await fixture.controller.switchComparison(to: options)
    try await fixture.show("README.md")

    #expect(fixture.controller.comparisonOptions.mode == .exact)
    #expect(fixture.shownRight == copied)
    #expect(fixture.controller.presentation.headers[.b]?.isEdited == true)
  }

  @Test func changeByAnotherAppWhileTheFileWasAwayIsAskedAboutOnceItShows() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    let copied = try #require(fixture.shownRight)
    try await fixture.show("VERSION")
    try Data("written by another app\n".utf8).write(
      to: fixture.folders.right.appending(path: "README.md"))

    try await fixture.show("README.md")
    await fixture.controller.diskWatch.reloadChangedFiles()

    #expect(fixture.prompts.questions == ["reload changed README.md"])
    #expect(fixture.shownRight == copied)
    #expect(fixture.markedPaths == ["README.md"])
  }

  @Test func savingAFileAwayThatAnotherAppChangedAsks() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    let copied = try #require(fixture.shownRight)
    try await fixture.show("VERSION")
    let other = Data("written by another app\n".utf8)
    try other.write(to: fixture.folders.right.appending(path: "README.md"))
    fixture.prompts.reloadsChangedResult = true

    #expect(!(await fixture.controller.saveChangedFiles()))

    #expect(fixture.prompts.questions == ["reload changed README.md"])
    #expect(try fixture.right("README.md") == other)
    #expect(fixture.markedPaths.isEmpty)
    try await fixture.show("README.md")
    #expect(fixture.shownRight == other)
    #expect(fixture.shownRight != copied)
  }

  /// Goes back to README.md, whose copies the navigator keeps, and waits until the window shows
  /// its headers above empty panes.
  private static func goBackToTheKeptFileUntilItsLinesAreThere(
    _ fixture: Fixture
  ) async throws {
    let index = try #require(fixture.collection.files.firstIndex { $0.path == "README.md" })
    fixture.controller.showFile(at: index)
    while !fixture.controller.waitsForComparison {
      await Task.yield()
    }
    #expect(fixture.controller.showsHeadersOnly)
    #expect(fixture.controller.presentation.headers[.b]?.isEdited == false)
  }

  @Test func saveAndCloseWhileTheKeptFileShowsOnlyItsHeadersWritesItsCopies() async throws {
    let fixture = try await Fixture(waitsForEveryFile: true)
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    try await Self.goBackToTheKeptFileUntilItsLinesAreThere(fixture)

    #expect(fixture.controller.canPerform(.saveAndClose))
    #expect(await fixture.controller.saveAndCloseWindow())

    #expect(try fixture.right("README.md") == fixture.left("README.md"))
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func saveInTheSheetWhileTheKeptFileShowsOnlyItsHeadersWritesItsCopies() async throws {
    let fixture = try await Fixture(waitsForEveryFile: true)
    fixture.prompts.unsavedChangesChoice = .save
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    try await Self.goBackToTheKeptFileUntilItsLinesAreThere(fixture)

    #expect(await fixture.controller.closeAskingFirst())

    #expect(fixture.prompts.questions == ["save changes to README.md"])
    #expect(try fixture.right("README.md") == fixture.left("README.md"))
    #expect(fixture.outcomes == ["saved"])
  }

  @Test func failedSavingWhileTheKeptFileShowsOnlyItsHeadersKeepsTheWindow() async throws {
    let fixture = try await Fixture(waitsForEveryFile: true)
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    let readme = fixture.folders.right.appending(path: "README.md")
    let before = try Data(contentsOf: readme)
    try await Self.goBackToTheKeptFileUntilItsLinesAreThere(fixture)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: fixture.folders.right.path)
    defer {
      do {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: fixture.folders.right.path)
      } catch {
        Issue.record("Could not make \(fixture.folders.right.path) writable again: \(error)")
      }
    }

    #expect(!(await fixture.controller.saveAndCloseWindow()))

    #expect(fixture.prompts.questions == ["failed saving README.md"])
    #expect(try Data(contentsOf: readme) == before)
    #expect(fixture.outcomes.isEmpty)
    #expect(fixture.controller.hasUnsavedChanges)
  }

  @Test func fileThatWentWithItsCopiesLeavesNothingBehind() async throws {
    let fixture = try await Fixture()
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    try await fixture.show("VERSION")
    #expect(fixture.controller.hasUnsavedChanges)

    for folder in [fixture.folders.left, fixture.folders.right] {
      try FileManager.default.removeItem(at: folder.appending(path: "README.md"))
    }
    await FolderWindowTests.wait(for: fixture.collection) {
      !$0.files.contains { $0.path == "README.md" }
    }

    #expect(!fixture.controller.hasUnsavedChanges)
    #expect(fixture.controller.window?.isDocumentEdited == false)
    #expect(!fixture.controller.canPerform(.save))
    #expect(fixture.markedPaths.isEmpty)
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions.isEmpty)
  }

  @Test func fileLeftForAnotherCountsOnceUntilTheOtherShows() async throws {
    let fixture = try await Fixture()
    fixture.prompts.unsavedChangesChoice = .save
    try await fixture.show("README.md")
    await fixture.copyAllToRight()
    var announcements: [String] = []
    fixture.controller.presentation.announce = { announcements.append($0) }

    let version = try #require(fixture.collection.files.firstIndex { $0.path == "VERSION" })
    fixture.controller.showFile(at: version)

    #expect(fixture.controller.changedFileNames == ["README.md"])
    #expect(fixture.markedPaths == ["README.md"])
    #expect(await fixture.controller.closeAskingFirst())
    #expect(fixture.prompts.questions == ["save changes to README.md"])
    #expect(announcements.contains("Saved README.md"))
    #expect(try fixture.right("README.md") == fixture.left("README.md"))
  }
}
