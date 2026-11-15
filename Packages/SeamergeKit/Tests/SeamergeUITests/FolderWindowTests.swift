import AppKit
import Testing

@testable import SeamergeUI

/// The window of two folders: it opens before they are compared, leaves identical files out and
/// says what it found.
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
