import AppKit
import Testing

@testable import SeamergeUI

/// The window that compares several files: going from file to file, what stays with each file,
/// the list while files come, and what is valid where.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CollectionWindowTests {
  @Test func nextFileShowsTheFileAfterThisOneAndIsInvalidAtTheEnd() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    let window = try #require(controller.window)
    #expect(!controller.canPerform(.previousFile))
    var titles = [window.title]

    while controller.canPerform(.nextFile) {
      #expect(window.tryToPerform(SessionCommand.nextFile.action, with: nil))
      await controller.fileLoad?.value
      titles.append(window.title)
    }

    #expect(titles == collection.files.map(\.path))
    #expect(window.subtitle.contains("File 5 of 5"))
    #expect(controller.canPerform(.previousFile))
    #expect(!controller.canPerform(.skipRemainingFiles))
    #expect(Keys.of(.nextFile, in: .diff) == Keys(SessionCommand.rightArrow, [.option, .command]))
    #expect(
      Keys.of(.previousFile, in: .diff) == Keys(SessionCommand.leftArrow, [.option, .command]))
  }

  @Test func windowOfOneSessionHasNoFilesToGoTo() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())

    #expect(!controller.canPerform(.nextFile))
    #expect(!controller.canPerform(.previousFile))
    #expect(controller.collectionLayout == nil)
  }

  @Test func fileShownAgainIsWhereTheWindowLeftIt() async throws {
    let folder = try SampleCollections.folder()
    let collection = FileCollection(files: try SampleCollections.commit(in: folder))
    let controller = try await Windows.controller(for: collection)
    #expect(controller.presentation.changes.blocks.count > 1)
    controller.presentation.jump(to: 1)

    controller.showFile(at: 2)
    await controller.fileLoad?.value
    #expect(controller.presentation.currentBlock == 0)
    controller.showFile(at: 0)
    await controller.fileLoad?.value

    #expect(controller.presentation.currentBlock == 1)
  }

  @Test func changingTheFileLeavesTheFocusWhereItIs() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    let window = try #require(controller.window)
    let focused = window.firstResponder

    controller.showNextFile(nil)
    await controller.fileLoad?.value

    #expect(window.firstResponder === focused)
  }

  @Test func sidebarShowsOnceASecondFileComes() async throws {
    let files = try SampleCollections.many(3, in: try SampleCollections.folder())
    let collection = FileCollection(
      origin: CollectionOrigin(repository: "/repository", run: nil), expectedCount: 3,
      quietPeriod: .seconds(60))
    collection.add(files[0])
    let controller = try await Windows.controller(for: collection)
    let layout = try #require(controller.collectionLayout)
    let toggle = NSMenuItem(
      title: "", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "")
    #expect(layout.sidebarItem.isCollapsed)
    #expect(!layout.validateUserInterfaceItem(toggle))
    #expect(!layout.fileList.receivingLine.isHidden)

    collection.add(files[1])

    #expect(!layout.sidebarItem.isCollapsed)
    #expect(layout.validateUserInterfaceItem(toggle))
    #expect(layout.fileList.tableView.numberOfRows == 2)
    #expect(controller.window?.subtitle.contains("File 1 of 3") == true)

    collection.add(files[2])

    #expect(layout.fileList.receivingLine.isHidden)
    #expect(layout.fileList.tableView.selectedRow == 0)
  }

  @Test func hiddenSidebarStaysHiddenInTheNextWindow() async throws {
    let defaults = UserDefaults.privateSuite()
    let files = try SampleCollections.commit(in: try SampleCollections.folder())
    let first = try await Windows.controller(
      for: FileCollection(files: files), settings: UserSettings(defaults: defaults))
    let layout = try #require(first.collectionLayout)
    #expect(!layout.sidebarItem.isCollapsed)

    layout.toggleSidebar(nil)

    let second = try await Windows.controller(
      for: FileCollection(files: files), settings: UserSettings(defaults: defaults))
    #expect(second.collectionLayout?.sidebarItem.isCollapsed == true)
  }

  @Test func rowsNameTheFileItsFolderAndWhatHappened() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    let table = try #require(controller.collectionLayout?.fileList.tableView)

    let labels = (0..<table.numberOfRows).map {
      table.view(atColumn: 0, row: $0, makeIfNecessary: true)?.accessibilityLabel() ?? ""
    }

    #expect(labels.contains("Discount.swift, Sources/Orders, New"))
    #expect(labels.contains("prices.txt, Deleted"))
    #expect(labels.contains("README.md, Modified"))
  }

  @Test func fileThatCannotBeComparedSaysWhyAndTheNextOneShowsItsLines() async throws {
    let folder = try SampleCollections.folder()
    var files = try SampleCollections.commit(in: folder)
    let binary = folder.appending(path: "logo.png")
    try Data([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]).write(to: binary)
    files[1] = CollectedFile(
      old: SessionFile(url: URL(filePath: "/dev/null"), label: "logo.png"),
      new: SessionFile(url: binary, label: "logo.png"),
      difftool: .init(path: "logo.png", filePosition: .init(number: 2, count: 5)))
    let controller = try await Windows.controller(for: FileCollection(files: files))

    controller.showFile(at: 1)
    await controller.fileLoad?.value
    #expect(controller.unavailable != nil)
    #expect(controller.canPerform(.nextFile))
    controller.showFile(at: 2)
    await controller.fileLoad?.value

    #expect(controller.unavailable == nil)
    #expect(controller.layout.sourcePanes.allSatisfy { !$0.pane.isHidden })
  }
}
