import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The welcome window: its title and size, the buttons that show the sheets of files, files
/// dropped on it, and what happens once the files of a sheet open.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct WelcomeWindowTests {
  @Test func windowIsTitledAfterWhatItIsAndKeepsItsSize() throws {
    let fixture = try WelcomeFixture()
    #expect(fixture.window.title == "Welcome")
    #expect(fixture.window.titleVisibility == .hidden)
    #expect(fixture.window.titlebarAppearsTransparent)
    #expect(!fixture.window.styleMask.contains(.resizable))
    #expect(fixture.window.collectionBehavior.contains(.fullScreenNone))
    #expect(fixture.window.toolbar == nil)
  }

  @Test func buttonsShowTheSheetsAndCompareFilesIsTheDefault() throws {
    let fixture = try WelcomeFixture()
    let sidebar = fixture.controller.sidebar
    #expect(
      [sidebar.compareFilesButton, sidebar.compareFoldersButton, sidebar.mergeFilesButton].map(
        \.title) == ["Compare Files…", "Compare Folders…", "Merge Files…"])
    #expect(sidebar.compareFilesButton.keyEquivalent == "\r")

    sidebar.mergeFilesButton.performClick(nil)
    let merge = try fixture.sheet()
    #expect(merge.purpose == .merge)
    #expect(fixture.window.isVisible)
    #expect(fixture.window.attachedSheet === merge.window)
    #expect(merge.window?.firstResponder === merge.fields[.left])

    fixture.controller.showCompareFiles(nil)
    let compare = try fixture.sheet()
    #expect(compare.purpose == .compare)
    #expect(fixture.window.attachedSheet === compare.window)
    #expect(merge.window?.sheetParent == nil)
  }

  @Test func everySheetBringsTheWindowToTheFrontWhileItIsOpenBehindAnother() throws {
    let fixture = try WelcomeFixture()
    fixture.controller.showWindow(nil)
    let other = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    defer { other.close() }
    let commands: [() -> Void] = [
      { fixture.controller.showMergeFiles(nil) },
      { fixture.controller.showCompareFiles(nil) },
      { fixture.controller.showCompareFolders(nil) },
    ]

    for command in commands {
      other.orderFront(nil)
      #expect(other.orderedIndex < fixture.window.orderedIndex)
      command()
      #expect(fixture.window.orderedIndex < other.orderedIndex)
    }
  }

  @Test func cancelEndsTheSheetAndKeepsTheWindow() throws {
    let fixture = try WelcomeFixture()
    fixture.controller.showMergeFiles(nil)

    try fixture.sheet().cancelOperation(nil)

    #expect(fixture.controller.filesSheet == nil)
    #expect(fixture.window.attachedSheet == nil)
    #expect(fixture.window.isVisible)
  }

  @Test func filesOpenedFromASheetAreRememberedAndCloseTheWindow() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let urls = [try files.file("a.txt"), try files.file("o.txt"), try files.file("b.txt")]
    #expect(fixture.controller.fill(with: urls))

    // The action of the button, as a click sends it once the button is released; a click in
    // the test would run the opening inside the loop that tracks the button.
    try fixture.sheet().openComparison(nil)
    await fixture.opener.nextOpening()
    await fixture.nextClose()

    let opened = FileComparison(left: urls[0], base: urls[1], right: urls[2])
    #expect(fixture.opener.opened == [opened])
    #expect(fixture.recentComparisons.comparisons == [opened])
    #expect(fixture.window.attachedSheet == nil)
    #expect(fixture.controller.filesSheet == nil)
  }

  @Test func twoFilesOrFoldersDroppedOnTheWindowOpenAtOnce() async throws {
    let files = try SampleFiles()
    let folders = try SampleFolders()
    let comparisons = [
      FileComparison(left: try files.file("old.txt"), right: try files.file("new.txt")),
      FileComparison(folders: folders.pair),
    ]
    for comparison in comparisons {
      let fixture = try WelcomeFixture()
      fixture.controller.showWindow(nil)
      let drag = DragInTest(files: [comparison.left, comparison.right])

      #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
      #expect(fixture.controller.sidebar.dropArea.dropAction == "Drop to Compare")
      #expect(fixture.controller.acceptDrop(drag, onto: nil))
      await fixture.opener.nextOpening()

      #expect(fixture.opener.opened == [comparison])
      #expect(fixture.controller.sidebar.dropArea.dropAction == nil)
      #expect(fixture.controller.filesSheet == nil)
    }
  }

  @Test func twoDroppedFilesOpenWithTheOlderOnTheLeftAsTheServiceOpensThem() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let (older, newer) = (try files.file("old.txt"), try files.file("new.txt"))
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
      ofItemAtPath: older.path(percentEncoded: false))

    #expect(fixture.controller.acceptDrop(DragInTest(files: [newer, older]), onto: nil))
    await fixture.opener.nextOpening()

    #expect(fixture.opener.opened == [FileComparison(left: older, right: newer)])
  }

  @Test func threeDroppedFilesFillTheSheetMergeFiles() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let urls = [try files.file("a.txt"), try files.file("o.txt"), try files.file("b.txt")]
    let drag = DragInTest(files: urls)

    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
    #expect(fixture.controller.sidebar.dropArea.dropAction == "Drop to Merge")
    #expect(fixture.controller.acceptDrop(drag, onto: nil))

    #expect(try fixture.sheet().purpose == .merge)
    #expect(try fixture.files() == urls)
    #expect(fixture.opener.opened.isEmpty)
  }

  @Test func oneEntryOrTwoThatDoNotGoTogetherFillTheSheetCompareFiles() throws {
    let files = try SampleFiles()
    let folder = try files.subfolder("folder")
    let file = try files.file("a.txt")
    for urls in [[file], [folder], [folder, file], [folder, folder]] {
      let fixture = try WelcomeFixture()

      #expect(fixture.controller.acceptDrop(DragInTest(files: urls), onto: nil))

      #expect(try fixture.sheet().purpose == .compare)
      #expect(try fixture.files().compactMap(\.self) == urls)
      #expect(fixture.opener.opened.isEmpty)
    }
  }

  @Test func whatNoSheetTakesIsRefusedAndSoIsADropOnAWindowWithASheet() throws {
    let files = try SampleFiles()
    let four = try (1...4).map { try files.file("\($0).txt") }
    let mixed = [four[0], four[1], try files.subfolder("folder")]
    let fixture = try WelcomeFixture()

    for urls in [four, mixed] {
      #expect(fixture.controller.operation(forDrag: DragInTest(files: urls), onto: nil) == [])
      #expect(!fixture.controller.acceptDrop(DragInTest(files: urls), onto: nil))
      #expect(fixture.controller.sidebar.dropArea.dropAction == nil)
      #expect(!fixture.controller.fill(with: urls))
    }
    fixture.controller.showCompareFiles(nil)
    let two = DragInTest(files: Array(four.prefix(2)))
    #expect(fixture.controller.operation(forDrag: two, onto: nil) == [])
    #expect(!fixture.controller.acceptDrop(two, onto: nil))
  }

  @Test func droppedFilesThatCannotBeOpenedStandInTheSheetWithTheirReason() async throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let comparison = FileComparison(left: try files.file("a.png"), right: try files.file("b.txt"))
    fixture.opener.failure = SessionLoadingError.binaryFile(comparison.left)

    #expect(
      fixture.controller.acceptDrop(
        DragInTest(files: [comparison.left, comparison.right]), onto: nil))
    await fixture.panels.nextFailure()

    #expect(try fixture.sheet().selection.comparison == comparison)
    #expect(fixture.recentComparisons.comparisons.isEmpty)
    #expect(fixture.window.isVisible)
  }

  @Test func filesFromTheDockAddToTheSheetThatIsShown() throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    let (a, b) = (try files.file("a.txt"), try files.file("b.txt"))

    #expect(fixture.controller.fill(with: [a]))
    #expect(fixture.controller.fill(with: [b]))

    #expect(try fixture.files() == [a, b])
    #expect(fixture.opener.opened.isEmpty)
  }

  @Test func sheetOfFilesWaitsForTheSheetSetUpGitIntegration() async throws {
    let files = try SampleFiles()
    let (fixture, _) = try integrationFixture(.kaleidoscope)
    fixture.controller.showWindow(nil)
    await fixture.controller.presentGitIntegration()
    let integration = try #require(fixture.controller.integrationSheet)
    let file = try files.file("a.txt")

    fixture.controller.compare(with: file)
    #expect(fixture.controller.filesSheet == nil)

    integration.cancelOperation(nil)
    var turns = 0
    while fixture.controller.filesSheet == nil && turns < 100 {
      await Task.yield()
      turns += 1
    }

    #expect(try fixture.files() == [file, nil])
    #expect(fixture.window.attachedSheet === (try fixture.sheet().window))
  }

  @Test func versionAndThePlaceToDropFilesTellVoiceOverWhatTheyAre() throws {
    let fixture = try WelcomeFixture()
    let texts = labelTexts(in: fixture.controller.sidebar)

    #expect(texts.contains("Seamerge"))
    #expect(texts.contains("Version 0.6.0"))
    #expect(fixture.controller.sidebar.dropArea.accessibilityLabel() == "Drop two files or folders")
    #expect(fixture.controller.sidebar.dropArea.accessibilityRole() == .staticText)
  }

  private func labelTexts(in view: NSView) -> [String] {
    ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(labelTexts)
  }
}
