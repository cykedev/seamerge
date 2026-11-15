import AppKit
import Testing

@testable import SeamergeUI

/// The window of two folders: it opens before they are compared, lists identical files only on
/// request, says what it found, follows the folders on disk and keeps the selection.
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

  @Test func changeOnDiskUpdatesTheListAndKeepsTheSelection() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    let readme = try #require(collection.files.firstIndex { $0.path == "README.md" })
    controller.showFile(at: readme)
    await controller.fileLoad?.value
    let table = try #require(controller.collectionLayout?.fileList.tableView)

    try folders.write("Sources/Orders/Invoice.swift", left: nil, right: "struct Invoice {}\n")
    try folders.write("1.1\n", to: folders.left.appending(path: "VERSION"))
    try FileManager.default.removeItem(at: folders.left.appending(path: "prices.txt"))
    await Self.wait(for: collection) {
      $0.files.contains { $0.path == "Sources/Orders/Invoice.swift" }
        && $0.files.first { $0.path == "VERSION" }?.change == .identical
        && !$0.files.contains { $0.path == "prices.txt" }
    }

    let listed = (0..<table.numberOfRows).compactMap {
      controller.collectionLayout?.fileList.files[$0].path
    }
    #expect(listed.contains("Sources/Orders/Invoice.swift"))
    #expect(!listed.contains("VERSION"))
    #expect(controller.shownFile?.path == "README.md")
    #expect(listed.indices.contains(table.selectedRow) && listed[table.selectedRow] == "README.md")
  }

  @Test func fileThatWentFromBothFoldersGivesWayToTheNextOne() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    let readme = try #require(collection.files.firstIndex { $0.path == "README.md" })
    controller.showFile(at: readme)
    await controller.fileLoad?.value

    for root in [folders.left, folders.right] {
      try FileManager.default.removeItem(at: root.appending(path: "README.md"))
    }
    await Self.wait(for: collection) { !$0.files.contains { $0.path == "README.md" } }
    await controller.fileLoad?.value

    #expect(
      controller.shownFile?.path
        == "Resources/Configuration/Environments/Production/prices-and-discounts-for-every-region.json"
    )
  }

  /// Thousands of changes at once, as a checkout makes them, are compared away from the main
  /// thread; beyond the limit of changes kept apart, everything is compared again.
  @Test(arguments: [1000, FolderComparisonRun.changeLimit + 1000])
  func thousandsOfChangesComeIntoTheList(count: Int) async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    let generated = folders.right.appending(path: "Generated", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)

    for index in 0..<count {
      try Data("\(index)\n".utf8).write(to: generated.appending(path: "File\(index).swift"))
    }
    await Self.wait(for: collection) {
      $0.files.count { $0.path.hasPrefix("Generated/") } == count
    }

    #expect(controller.collectionLayout?.fileList.tableView.numberOfRows == 6 + count)
  }

  @Test func nextFileShowsWhatChangedOnDiskSinceItWasReadAhead() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    // The system may still report the files written before the comparison; once a file
    // written now is in the list, it has reported everything before it.
    try folders.write("zz-marker.txt", left: nil, right: "marker\n")
    await Self.wait(for: collection) { $0.files.contains { $0.path == "zz-marker.txt" } }
    let readme = try #require(collection.files.firstIndex { $0.path == "README.md" })
    controller.showFile(at: readme)
    await controller.fileLoad?.value
    let next = try #require(controller.neighborIndex(forward: true))
    let path = collection.files[next].path
    #expect(controller.loadedFiles.keys.contains(collection.files[next]), "Read ahead")

    try folders.write("{\n  \"retries\": 7\n}\n", to: folders.right.appending(path: path))
    var changes = 0
    await Self.wait(for: collection) { _ in
      changes += 1
      return changes > 1
    }
    controller.showNextFile(nil)
    await controller.fileLoad?.value

    #expect(controller.shownFile?.path == path)
    let right = controller.presentation.changes.session.file(for: .b)?.text
    #expect(right?.contains("7") == true)
  }

  /// A reading that began before a change on disk and ends after it is not kept; this follows
  /// the order of the two without waiting for a reading.
  @Test func readingThatStartedBeforeAChangeOnDiskIsNotKept() async throws {
    let folders = try SampleFolders()
    try folders.fillWithProject()
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    let next = try #require(controller.neighborIndex(forward: true))
    let file = collection.files[next]
    let loaded = try await SessionWindowController.load(file, mode: .windowDefault)
    let generation = controller.diskGeneration

    collection.take(.replaced(collection.files))
    controller.keep(loaded, of: file, readIn: generation)

    #expect(controller.loadedFiles[file] == nil)
    controller.keep(loaded, of: file, readIn: controller.diskGeneration)
    #expect(controller.loadedFiles[file] != nil)
  }

  @Test func fileInViewThatCannotBeReadAnyMoreSaysWhy() async throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "abc\n", right: "abd\n")
    let collection = await FileCollection.compared(folders)
    let controller = try await Windows.controller(for: collection)
    #expect(controller.shownFile?.path == "notes.txt")
    #expect(controller.unavailable == nil)

    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: folders.right.appending(path: "notes.txt").path)
    await Self.wait(for: collection) {
      if case .unreadable = $0.files.first?.change { true } else { false }
    }
    await controller.fileLoad?.value

    #expect(controller.unavailable != nil)
  }

  /// Waits until `condition` holds for `collection`, looking each time the collection changes;
  /// gives up when the test is cancelled.
  static func wait(
    for collection: FileCollection, until condition: (FileCollection) -> Bool
  ) async {
    let (changes, sink) = AsyncStream.makeStream(of: Void.self)
    let window = collection.onChange
    collection.onChange = { change in
      window?(change)
      sink.yield()
    }
    defer { collection.onChange = window }
    var iterator = changes.makeAsyncIterator()
    while !condition(collection) {
      guard await iterator.next() != nil else { return }
    }
  }
}
