import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Folders in the sheet Compare Files: two of them are compared file by file, a folder with a
/// file or with itself is not, and Compare Folders… asks for the left folder.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CompareFoldersTests {
  @Test func twoFoldersAreComparedFileByFile() async throws {
    let folders = try SampleFolders()
    let fixture = CompareFilesFixture()

    #expect(fixture.controller.fill(with: [folders.left, folders.right]))

    #expect(fixture.captions == ["Left Folder", "Right Folder"])
    #expect(fixture.controller.openButton.title == "Compare")
    #expect(fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue.isEmpty)

    fixture.controller.openComparison(nil)
    await fixture.opener.nextOpening()

    let expected = FileComparison(folders: folders.pair)
    #expect(fixture.opener.opened == [expected])
    #expect(expected.kind == .diff)
  }

  @Test func folderAndFileAreNotCompared() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "notes\n", right: nil)
    let fixture = CompareFilesFixture()

    #expect(
      fixture.controller.fill(with: [folders.left, folders.left.appending(path: "notes.txt")]))

    #expect(!fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue == "Choose two files or two folders.")
    #expect(fixture.captions == ["Left Folder", "Right"])
    #expect(fixture.controller.selection.comparison == nil)
  }

  @Test func sameFolderTwiceIsNotCompared() throws {
    let folders = try SampleFolders()
    let fixture = CompareFilesFixture()

    #expect(fixture.controller.fill(with: [folders.left, folders.left]))

    #expect(!fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue == "Choose two different folders.")
  }

  @Test func fieldsOfAComparisonChooseFilesOrFolders() async throws {
    let folders = try SampleFolders()
    let fixture = CompareFilesFixture()
    fixture.panels.files = [folders.left]

    fixture.controller.fileFieldDidAskToChoose(try fixture.field(.left))
    await fixture.panels.nextChoice()
    fixture.controller.fileFieldDidAskToChoose(try fixture.field(.right))
    await fixture.panels.nextChoice()

    #expect(fixture.panels.fileChoices == [.fileOrFolder, .fileOrFolder])
    #expect(fixture.panels.roles == ["Left", "Right Folder"])
    #expect(fixture.controller.selection[.left] == folders.left)
  }

  @Test func compareFoldersAsksForTheLeftFolder() async throws {
    let folders = try SampleFolders()
    let fixture = try WelcomeFixture()
    fixture.panels.files = [folders.left]

    fixture.controller.showCompareFolders(nil)
    let sheet = try fixture.sheet()
    #expect(sheet.selection.isEmpty)
    await fixture.panels.nextChoice()

    #expect(fixture.panels.fileChoices == [.folder])
    #expect(fixture.panels.roles == ["Left Folder"])
    #expect(sheet.selection[.left] == folders.left)
    #expect(fixture.window.attachedSheet === sheet.window)
  }

  @Test func compareFoldersKeepsWhatTheSheetHoldsUntilAFolderIsChosen() async throws {
    let folders = try SampleFolders()
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let (a, b) = (try files.file("a.txt"), try files.file("b.txt"))
    #expect(fixture.controller.fill(with: [a, b]))

    fixture.controller.showCompareFolders(nil)
    await fixture.panels.nextChoice()
    #expect(try fixture.files() == [a, b], "cancelled: nothing is lost")

    fixture.panels.files = [folders.left]
    fixture.controller.showCompareFolders(nil)
    await fixture.panels.nextChoice()
    #expect(try fixture.files() == [folders.left, b])
  }

  @Test func folderDroppedOnTheSheetTakesTheFirstFreeField() throws {
    let folders = try SampleFolders()
    let fixture = CompareFilesFixture()

    let drag = DragInTest(files: [folders.left])
    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
    #expect(fixture.controller.acceptDrop(drag, onto: nil))
    #expect(fixture.controller.acceptDrop(DragInTest(files: [folders.right]), onto: nil))

    #expect(fixture.controller.selection.comparison == FileComparison(folders: folders.pair))
  }

  @Test func recentComparisonOfFoldersIsKeptAsOne() throws {
    let folders = try SampleFolders()
    let name = "SeamergeUITests.\(UUID().uuidString)"
    let defaults = UserDefaults.privateSuite(named: name)
    defer { defaults.removePersistentDomain(forName: name) }
    let comparison = FileComparison(folders: folders.pair)

    RecentComparisons(defaults: defaults).add(comparison)

    let kept = RecentComparisons(defaults: defaults).comparisons
    #expect(kept == [comparison])
    #expect(kept.first?.comparesFolders == true)
    #expect(kept.first?.accessibilityTitle == "Compare the folder Orders 1.0 with Orders 1.1")
  }
}
