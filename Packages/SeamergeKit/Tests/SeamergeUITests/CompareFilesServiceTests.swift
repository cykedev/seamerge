import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The window Compare Files as the service Compare with Seamerge hands it a selection: what it
/// replaces, where the focus goes, and what it says about a selection it does not compare.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CompareFilesServiceTests {
  @Test func oneFileGoesLeftInPlaceOfWhatWasThereWithTheFocusOnRight() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let file = try files.file("a.txt")
    #expect(fixture.controller.fill(with: [try files.file("x.txt"), try files.file("y.txt")]))

    fixture.controller.compare(with: file)
    defer { fixture.window.close() }

    #expect(fixture.controller.selection[.left] == file)
    #expect(fixture.controller.selection[.base] == nil)
    #expect(fixture.controller.selection[.right] == nil)
    #expect(fixture.window.isVisible)
    #expect(fixture.window.firstResponder === (try fixture.field(.right)))
    #expect(fixture.announcements.last == "a.txt added as Left")
  }

  @Test func oneFolderGoesLeftAndNamesBothOuterFieldsForFolders() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let folder = try files.subfolder("folder")

    fixture.controller.compare(with: URL(filePath: folder.path(percentEncoded: false)))
    defer { fixture.window.close() }

    #expect(fixture.controller.selection[.left] == folder)
    #expect(fixture.captions == ["Left Folder", "Base (Optional)", "Right Folder"])
    #expect(fixture.window.firstResponder === (try fixture.field(.right)))
  }

  @Test func threeFilesFillEveryFieldInPlaceOfWhatWasThere() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let urls = [try files.file("a.txt"), try files.file("base.txt"), try files.file("b.txt")]
    #expect(
      fixture.controller.fill(with: [try files.subfolder("old"), try files.subfolder("new")]))

    fixture.controller.show(replacingFilesWith: urls)
    defer { fixture.window.close() }

    #expect(FileSlot.allCases.map { fixture.controller.selection[$0] } == urls)
    #expect(fixture.captions == ["A", "Base", "B"])
    #expect(fixture.controller.problemLabel.stringValue.isEmpty)
    #expect(fixture.controller.openButton.isEnabled)
  }

  @Test func selectionThatIsNotComparedEmptiesTheFieldsAndSaysWhatSeamergeCompares() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let sentence = "Seamerge compares two or three files, or two folders."
    #expect(fixture.controller.fill(with: [try files.file("x.txt")]))

    fixture.controller.showUnsupportedSelection()
    defer { fixture.window.close() }

    #expect(fixture.controller.selection.isEmpty)
    #expect(fixture.window.isVisible)
    #expect(fixture.controller.problemLabel.stringValue == sentence)
    #expect(fixture.announcements.last == sentence)
    #expect(!fixture.controller.openButton.isEnabled)
    fixture.controller.showWindow(nil)
    #expect(fixture.controller.problemLabel.stringValue == sentence, "it stays while shown again")
  }

  @Test func sentenceAboutTheSelectionGoesOnceTheFieldsChange() throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let four = try (1...4).map { try files.file("\($0).txt") }

    fixture.controller.show(replacingFilesWith: four)
    defer { fixture.window.close() }
    #expect(fixture.controller.selection.isEmpty)
    #expect(!fixture.controller.problemLabel.stringValue.isEmpty)

    #expect(fixture.controller.acceptDrop(DragInTest(files: [four[0]]), onto: nil))
    #expect(fixture.controller.problemLabel.stringValue.isEmpty)
  }

  @Test func filesThatCouldNotBeOpenedStandInTheFieldsWithTheirReason() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let comparison = FileComparison(left: try files.file("old.png"), right: try files.file("new"))
    #expect(fixture.controller.fill(with: [try files.file("x.txt")]))

    fixture.controller.showFailure(
      SessionLoadingError.binaryFile(comparison.left), opening: comparison)
    defer { fixture.window.close() }
    await fixture.panels.nextFailure()

    #expect(fixture.window.isVisible)
    #expect(fixture.controller.selection.comparison == comparison)
    #expect(fixture.panels.failures == ["“old.png” isn’t a text file."])
    #expect(fixture.controller.openButton.isEnabled)
    #expect(fixture.recentComparisons.comparisons.isEmpty)
  }

  @Test func foldersThatCouldNotBeOpenedStandInTheOuterFields() async throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    let comparison = FileComparison(
      folders: FolderPair(left: try files.subfolder("old"), right: try files.subfolder("new")))

    fixture.controller.showFailure(SessionLoadingError.comparisonFailed, opening: comparison)
    defer { fixture.window.close() }
    await fixture.panels.nextFailure()

    #expect(fixture.controller.selection.comparison == comparison)
    #expect(fixture.captions == ["Left Folder", "Base (Optional)", "Right Folder"])
    #expect(fixture.panels.failures.count == 1)
  }
}
