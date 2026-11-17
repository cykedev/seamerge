import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The welcome window as the service Compare with Seamerge hands it a selection: which sheet it
/// shows, what the sheet replaces, where the focus goes, and what it says about a selection it
/// does not compare.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CompareFilesServiceTests {
  @Test func oneFileGoesLeftInPlaceOfWhatWasThereWithTheFocusOnRight() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let file = try files.file("a.txt")
    #expect(fixture.controller.fill(with: [try files.file("x.txt"), try files.file("y.txt")]))

    fixture.controller.compare(with: file)

    let sheet = try fixture.sheet()
    #expect(sheet.purpose == .compare)
    #expect(try fixture.files() == [file, nil])
    #expect(fixture.window.isVisible)
    #expect(fixture.window.attachedSheet === sheet.window)
    #expect(sheet.window?.firstResponder === sheet.fields[.right])
    #expect(fixture.announcements.last == "a.txt added as Left")
  }

  @Test func oneFolderGoesLeftAndNamesBothFieldsForFolders() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let folder = try files.subfolder("folder")

    fixture.controller.compare(with: URL(filePath: folder.path(percentEncoded: false)))

    #expect(try fixture.files() == [folder, nil])
    #expect(try fixture.captions() == ["Left Folder", "Right Folder"])
    #expect(try fixture.sheet().window?.firstResponder === fixture.sheet().fields[.right])
  }

  @Test func threeFilesFillTheSheetMergeFilesInPlaceOfWhatWasThere() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let urls = [try files.file("a.txt"), try files.file("base.txt"), try files.file("b.txt")]
    #expect(
      fixture.controller.fill(with: [try files.subfolder("old"), try files.subfolder("new")]))

    fixture.controller.show(replacingFilesWith: urls)

    let sheet = try fixture.sheet()
    #expect(sheet.purpose == .merge)
    #expect(fixture.window.attachedSheet === sheet.window)
    #expect(try fixture.files() == urls)
    #expect(try fixture.captions() == ["A", "Base", "B"])
    #expect(sheet.problemLabel.stringValue.isEmpty)
    #expect(sheet.openButton.isEnabled)
  }

  @Test func selectionThatIsNotComparedEmptiesTheFieldsAndSaysWhatSeamergeCompares() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let sentence = "Seamerge compares two or three files, or two folders."
    #expect(fixture.controller.fill(with: [try files.file("x.txt")]))

    fixture.controller.showUnsupportedSelection()

    let sheet = try fixture.sheet()
    #expect(sheet.selection.isEmpty)
    #expect(fixture.window.isVisible)
    #expect(sheet.problemLabel.stringValue == sentence)
    #expect(fixture.announcements.last == sentence)
    #expect(!sheet.openButton.isEnabled)
    fixture.controller.showWindow(nil)
    #expect(sheet.problemLabel.stringValue == sentence, "it stays while shown again")
  }

  @Test func sentenceAboutTheSelectionGoesOnceTheFieldsChange() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let four = try (1...4).map { try files.file("\($0).txt") }

    fixture.controller.show(replacingFilesWith: four)
    let sheet = try fixture.sheet()
    #expect(sheet.selection.isEmpty)
    #expect(!sheet.problemLabel.stringValue.isEmpty)

    #expect(sheet.acceptDrop(DragInTest(files: [four[0]]), onto: nil))
    #expect(sheet.problemLabel.stringValue.isEmpty)
  }

  @Test func filesThatCouldNotBeOpenedStandInTheFieldsWithTheirReason() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(left: try files.file("old.png"), right: try files.file("new"))
    #expect(fixture.controller.fill(with: [try files.file("x.txt")]))

    fixture.controller.showFailure(
      SessionLoadingError.binaryFile(comparison.left), opening: comparison)
    await fixture.panels.nextFailure()

    let sheet = try fixture.sheet()
    #expect(fixture.window.isVisible)
    #expect(sheet.selection.comparison == comparison)
    #expect(fixture.panels.failures == ["“old.png” isn’t a text file."])
    #expect(sheet.openButton.isEnabled)
    #expect(fixture.recentComparisons.comparisons.isEmpty)
  }

  @Test func mergeThatCouldNotBeOpenedStandsInTheSheetMergeFiles() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(
      left: try files.file("a.txt"), base: try files.file("o.txt"), right: try files.file("b.png"))

    fixture.controller.showFailure(SessionLoadingError.comparisonFailed, opening: comparison)
    await fixture.panels.nextFailure()

    #expect(try fixture.sheet().purpose == .merge)
    #expect(try fixture.sheet().selection.comparison == comparison)
  }

  @Test func foldersThatCouldNotBeOpenedStandInTheFields() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(
      folders: FolderPair(left: try files.subfolder("old"), right: try files.subfolder("new")))

    fixture.controller.showFailure(SessionLoadingError.comparisonFailed, opening: comparison)
    await fixture.panels.nextFailure()

    #expect(try fixture.sheet().selection.comparison == comparison)
    #expect(try fixture.captions() == ["Left Folder", "Right Folder"])
    #expect(fixture.panels.failures.count == 1)
  }
}
