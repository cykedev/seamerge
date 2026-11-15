import AppKit
import Testing

@testable import SeamergeUI

/// The window of two folders: it opens before they are compared, lists identical files only on
/// request and says what it found.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FolderWindowTests {
  @Test func windowOpensAtOnceSaysItComparesAndShowsTheFirstFileThatDiffers() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links")))
    let controller = try await Windows.controller(for: collection)
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }
    let fileList = try #require(controller.collectionLayout?.fileList)

    #expect(controller.collectionPlaceholder == .comparing)
    #expect(controller.collectionLayout?.sidebarItem.isCollapsed == false)
    #expect(!controller.canPerform(.nextChange))
    #expect(!controller.canPerform(.nextFile))
    #expect(fileList.statusLine.accessibilityLabel() == "Comparing Files…")
    #expect(controller.window?.title == "Orders 1.0 ↔ Orders 1.1")

    collection.startComparing()
    await collection.waitUntilCompared()
    await controller.fileLoad?.value

    #expect(controller.collectionPlaceholder == nil)
    #expect(controller.shownFile?.path == "prices.txt")
    #expect(controller.window?.title == "prices.txt")
    #expect(controller.window?.subtitle.contains("File 1 of 6 · Orders 1.0 ↔ Orders 1.1") == true)
    #expect(fileList.statusLine.accessibilityLabel() == "6 of 9 files differ")
    #expect(announcements.first == "prices.txt (Deleted)")
    #expect(announcements.last == "6 of 9 files differ")
    #expect(controller.canPerform(.nextFile))
  }

  @Test func progressCountsTheComparedFiles() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let comparer = FolderComparer(
      folders: folders.pair, linkFolder: folders.folder.appending(path: "links"))
    let collection = FileCollection(comparer: comparer)
    let controller = try await Windows.controller(for: collection)
    let fileList = try #require(controller.collectionLayout?.fileList)
    let files = comparer.pairs(at: "").map {
      comparer.file(for: $0, change: comparer.change(of: $0))
    }

    collection.take(.listed(Array(files.prefix(3)), waiting: 1_197))

    // The count is written as the user's locale writes numbers.
    #expect(
      fileList.statusLine.accessibilityLabel() == "Comparing 3 of \(1_200.formatted()) Files…")
  }

  @Test func identicalFilesShowOnlyWithShowIdenticalFilesWhichNewWindowsRemember() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let defaults = UserDefaults.privateSuite()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(
      for: collection, settings: UserSettings(defaults: defaults))
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let item = NSMenuItem(
      title: "", action: SessionCommand.toggleIdenticalFiles.action, keyEquivalent: "")
    #expect(table.numberOfRows == 6)
    #expect(controller.validateUserInterfaceItem(item))
    #expect(item.state == .off)

    #expect(
      controller.window?.tryToPerform(item.action ?? #selector(NSObject.copy), with: item) == true)

    #expect(table.numberOfRows == 9)
    #expect(controller.validateUserInterfaceItem(item))
    #expect(item.state == .on)
    let next = try await Windows.controller(
      for: await FileCollection.compared(folders), settings: UserSettings(defaults: defaults))
    #expect(next.collectionLayout?.fileList.tableView.numberOfRows == 9)
  }

  @Test func foldersCommandsAreValidOnlyWhereTheyWork() async throws {
    let gitCollection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let gitWindow = try await Windows.controller(for: gitCollection)
    let single = try Windows.controller(for: try await SampleDiffs.greeting())

    #expect(!gitWindow.canPerform(.toggleIdenticalFiles))
    #expect(!single.canPerform(.toggleIdenticalFiles))
  }

  @Test func foldersWithTheSameFilesSaySoInPlaceOfTheLines() async throws {
    let folders = try SampleFolders()
    try folders.write("README.md", left: "same\n", right: "same\n")
    let collection = await FileCollection.compared(folders)

    let controller = try await Windows.controller(for: collection)

    #expect(controller.collectionPlaceholder == .sameFiles)
    #expect(controller.collectionLayout?.fileList.tableView.numberOfRows == 0)
    #expect(
      controller.collectionLayout?.fileList.statusLine.accessibilityLabel()
        == "0 of 1 files differ")
  }
}
