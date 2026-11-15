import AppKit
import Testing

@testable import SeamergeUI

/// Folders in the window Compare Files: two of them are compared without a base, a folder with a
/// file or with itself is not, and File > Compare Folders… asks for the left folder.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CompareFoldersTests {
  @Test func twoFoldersAreComparedWithoutABaseAndRemembered() async throws {
    let folders = try SampleFolders()
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()

    #expect(fixture.controller.fill(with: [folders.left, folders.right]))

    #expect(fixture.captions == ["Left Folder", "Base (Optional)", "Right Folder"])
    #expect(try !fixture.field(.base).isEnabled)
    #expect(try fixture.field(.base).toolTip == "Folders are compared without a base.")
    #expect(try !fixture.field(.base).acceptsFirstResponder)
    #expect(fixture.controller.openButton.title == "Compare")
    #expect(fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue.isEmpty)
    let file = DragInTest(files: [try files.file("base.txt")])
    #expect(fixture.controller.operation(forDrag: file, onto: .base) == [])

    fixture.controller.openComparison(nil)
    await fixture.delegate.nextOpening()

    let expected = FileComparison(folders: folders.pair)
    #expect(fixture.delegate.opened == [expected])
    #expect(expected.kind == .diff)
    #expect(fixture.recentComparisons.comparisons == [expected])
  }

  @Test func folderAndFileAreNotCompared() throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "notes\n", right: nil)
    let fixture = try CompareFilesFixture()

    #expect(
      fixture.controller.fill(with: [folders.left, folders.left.appending(path: "notes.txt")]))

    #expect(!fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue == "Choose two files or two folders.")
    #expect(fixture.captions == ["Left Folder", "Base (Optional)", "Right"])
    #expect(fixture.controller.selection.comparison == nil)
  }

  @Test func sameFolderTwiceIsNotCompared() throws {
    let folders = try SampleFolders()
    let fixture = try CompareFilesFixture()

    #expect(fixture.controller.fill(with: [folders.left, folders.left]))

    #expect(!fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue == "Choose two different folders.")
  }

  @Test func baseThatHoldsAFileStopsAComparisonOfFolders() throws {
    let folders = try SampleFolders()
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    #expect(fixture.controller.fill(with: [try files.file("base.txt")]))
    fixture.controller.fill([.base: try #require(fixture.controller.selection[.left])])
    fixture.controller.clear(.left)

    #expect(fixture.controller.fill(with: [folders.left, folders.right]))

    #expect(try fixture.field(.base).isEnabled, "The base stays clearable")
    #expect(!fixture.controller.openButton.isEnabled)
    #expect(fixture.controller.problemLabel.stringValue == "Folders are compared without a base.")
  }

  @Test func outerFieldsChooseFilesOrFoldersAndTheBaseFilesOnly() async throws {
    let folders = try SampleFolders()
    let fixture = try CompareFilesFixture()
    fixture.panels.files = [folders.left]

    fixture.controller.fileFieldDidAskToChoose(try fixture.field(.left))
    await fixture.panels.nextChoice()
    fixture.controller.fileFieldDidAskToChoose(try fixture.field(.base))
    await fixture.panels.nextChoice()

    #expect(fixture.panels.fileChoices == [.fileOrFolder, .file])
    #expect(fixture.controller.selection[.left] == folders.left)
  }

  @Test func compareFoldersEmptiesTheFieldsAndAsksForTheLeftFolder() async throws {
    let folders = try SampleFolders()
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    #expect(fixture.controller.fill(with: [try files.file("a.txt"), try files.file("b.txt")]))
    fixture.panels.files = [folders.left]

    fixture.controller.compareFolders()
    #expect(fixture.controller.selection[.right] == nil)
    await fixture.panels.nextChoice()

    #expect(fixture.panels.fileChoices == [.folder])
    #expect(fixture.panels.roles == ["Left Folder"])
    #expect(fixture.controller.selection[.left] == folders.left)
    #expect(fixture.captions == ["Left Folder", "Base (Optional)", "Right Folder"])
  }

  @Test func folderDroppedOnTheWindowTakesTheFirstFreeOuterField() throws {
    let folders = try SampleFolders()
    let fixture = try CompareFilesFixture()

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
