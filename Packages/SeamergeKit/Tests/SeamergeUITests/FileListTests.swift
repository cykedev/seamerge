import AppKit
import FolderCompareTestSupport
import GitSupport
import MergeModel
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// The list of the files in the sidebar, grouped by folder: headings that cannot be selected,
/// the keys and Next File going over them, the selection that stays with its file as files come,
/// what VoiceOver reads, and where the dot of unsaved changes stands.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct FileListTests {
  /// What VoiceOver reads for each row of the list of `controller`.
  private static func labels(in controller: SessionWindowController) throws -> [String] {
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    return (0..<table.numberOfRows).map {
      table.view(atColumn: 0, row: $0, makeIfNecessary: true)?.accessibilityLabel() ?? ""
    }
  }

  /// What VoiceOver reads for the selected row of the list of `controller`.
  private static func selectedLabel(in controller: SessionWindowController) throws -> String? {
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    guard table.selectedRow >= 0 else { return nil }
    return table.view(atColumn: 0, row: table.selectedRow, makeIfNecessary: true)?
      .accessibilityLabel()
  }

  /// Presses the arrow key `key` in the list of `controller`, as the keyboard does.
  private static func press(_ key: Int, in controller: SessionWindowController) throws {
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let window = try #require(controller.window)
    let characters = String(Character(try #require(Unicode.Scalar(key))))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false,
        keyCode: key == NSDownArrowFunctionKey ? 125 : 126))
    table.keyDown(with: event)
  }

  @Test func rowsShowTheFilesAtTheTopFirstThenEachFolderAsAHeadingAboveItsFiles() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let deep = "Resources/Configuration/Environments/Production"

    #expect(
      try Self.labels(in: controller) == [
        "README.md, Modified", "prices.txt, Deleted", "Folder, Sources/Orders",
        "OrderService.swift, Sources/Orders, Modified", "Discount.swift, Sources/Orders, New",
        "Folder, \(deep)", "prices-and-discounts-for-every-region.json, \(deep), Modified",
      ])
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    #expect(table.view(atColumn: 0, row: 5, makeIfNecessary: true)?.toolTip == deep)
    #expect(
      table.view(atColumn: 0, row: 0, makeIfNecessary: true)?.toolTip
        == "README.md (Modified)")
    #expect(controller.collectionNavigator?.shownFile?.path == "README.md")
    #expect(controller.window?.subtitle.contains("File 1 of 5") == true)
  }

  @Test func headingsCannotBeSelectedAndTheArrowKeysGoOverThem() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let fileList = try #require(controller.collectionLayout?.fileList)
    let table = fileList.tableView
    for row in 0..<table.numberOfRows {
      let isHeading = [2, 5].contains(row)
      #expect(fileList.tableView(table, shouldSelectRow: row) == !isHeading, "row \(row)")
      #expect(fileList.tableView(table, isGroupRow: row) == isHeading, "row \(row)")
    }
    controller.window?.makeFirstResponder(table)
    try Self.press(NSDownArrowFunctionKey, in: controller)
    await controller.fileLoad?.value

    try Self.press(NSDownArrowFunctionKey, in: controller)
    await controller.fileLoad?.value

    #expect(table.selectedRow == 3)
    #expect(controller.collectionNavigator?.shownFile?.path == "Sources/Orders/OrderService.swift")
    #expect(controller.window?.subtitle.contains("File 3 of 5") == true)

    try Self.press(NSUpArrowFunctionKey, in: controller)
    await controller.fileLoad?.value

    #expect(table.selectedRow == 1)
    #expect(controller.collectionNavigator?.shownFile?.path == "prices.txt")
  }

  @Test func nextFileGoesOverTheHeadingsInTheOrderOfTheList() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    var shown = [try Self.selectedLabel(in: controller)]

    while controller.canPerform(.nextFile) {
      controller.showNextFile(nil)
      await controller.fileLoad?.value
      shown.append(try Self.selectedLabel(in: controller))
    }

    #expect(
      shown.compactMap { $0?.components(separatedBy: ", ").first } == [
        "README.md", "prices.txt", "OrderService.swift", "Discount.swift",
        "prices-and-discounts-for-every-region.json",
      ])
  }

  @Test func fileThatComesInAnEarlierFolderLeavesTheSelectedFileWhereItStands() async throws {
    let files = try SampleCollections.many(60, in: try SampleCollections.folder())
    let collection = FileCollection(
      origin: CollectionOrigin(repository: "/repository", run: nil), expectedCount: 60,
      quietPeriod: .seconds(60))
    for (index, file) in files.enumerated() where ![3, 14].contains(index) {
      collection.add(file)
    }
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let clipView = try #require(table.enclosingScrollView?.contentView)
    let selected = try #require(collection.files.firstIndex { $0.path == files[45].path })
    controller.showFile(at: selected)
    await controller.fileLoad?.value
    let before = table.rect(ofRow: table.selectedRow).minY - clipView.bounds.minY
    try #require(clipView.bounds.minY > 0, "The list scrolled to the file")

    collection.add(files[3])
    collection.add(files[14])

    #expect(controller.collectionNavigator?.shownFile?.path == files[45].path)
    #expect(try Self.selectedLabel(in: controller)?.hasPrefix("File45.swift, ") == true)
    #expect(table.rect(ofRow: table.selectedRow).minY - clipView.bounds.minY == before)
    #expect(controller.window?.subtitle.contains("File 46 of 60") == true)
  }

  @Test func headingThatStaysAtTheTopHasTheWindowBackgroundAndOneInItsPlaceNone() async throws {
    let collection = FileCollection(
      files: try SampleCollections.many(80, in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let window = try #require(controller.window)

    table.scroll(CGPoint(x: 0, y: table.rect(ofRow: 16).minY))
    window.contentView?.layoutSubtreeIfNeeded()
    table.displayIfNeeded()

    let headings = (0..<table.numberOfRows).filter {
      table.view(atColumn: 0, row: $0, makeIfNecessary: false) is FolderHeadingCell
    }
    .compactMap { table.rowView(atRow: $0, makeIfNecessary: false) }
    let standing = try #require(headings.first { $0.isFloating })
    let inPlace = try #require(headings.first { !$0.isFloating })
    let background = try #require(
      Contrast.resolve(.windowBackgroundColor, in: window.effectiveAppearance))
    // A point at the end of the row, where the heading has no text.
    let color = { (row: NSTableRowView) throws -> NSColor in
      let bitmap = try #require(row.bitmapImageRepForCachingDisplay(in: row.bounds))
      row.cacheDisplay(in: row.bounds, to: bitmap)
      return try #require(
        bitmap.colorAt(x: bitmap.pixelsWide - 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }

    let standingColor = try color(standing)
    #expect(standingColor.alphaComponent == 1)
    #expect(Contrast.ratio(standingColor, background) < 1.01)
    #expect(try color(inPlace).alphaComponent == 0)
  }

  @Test func headingRowIsDrawnAgainWheneverItBeginsOrStopsToStayAtTheTop() async throws {
    let collection = FileCollection(
      files: try SampleCollections.many(80, in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let window = try #require(controller.window)
    let inset = table.enclosingScrollView?.contentInsets.top ?? 0
    let headingRows = {
      (0..<table.numberOfRows).compactMap { table.rowView(atRow: $0, makeIfNecessary: false) }
        .filter { $0 is FolderHeadingRowView }
    }
    // Without a screen nothing draws: each row counts as drawn, standing or not, until
    // something asks for it again.
    var drawnStanding: [ObjectIdentifier: Bool] = [:]
    let markDrawn = {
      for row in headingRows() {
        row.needsDisplay = false
        drawnStanding[ObjectIdentifier(row)] = row.isFloating
      }
    }
    var changedRows = 0

    // Back and forth over the list, with the same rows reused, without reloading.
    for target in [0, 14, 30, 2, 45, 0] {
      table.scroll(CGPoint(x: 0, y: table.rect(ofRow: target).minY - inset))
      window.contentView?.layoutSubtreeIfNeeded()
      for row in headingRows() {
        guard let drawn = drawnStanding[ObjectIdentifier(row)], drawn != row.isFloating else {
          continue
        }
        changedRows += 1
        #expect(row.needsDisplay, "Drawn again after it began or stopped to stay at the top")
      }
      markDrawn()
    }

    #expect(changedRows > 0, "A row began or stopped to stay at the top")
  }

  @Test func fileScrolledIntoViewStandsBelowTheHeadingOfItsFolder() async throws {
    let collection = FileCollection(
      files: try SampleCollections.many(80, in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let table = try #require(controller.collectionLayout?.fileList.tableView)
    let scrollView = try #require(table.enclosingScrollView)
    controller.showFile(at: 79)
    await controller.fileLoad?.value

    // File 12 stands two rows below the heading of its folder, out of view above; the table
    // scrolls it into view below the heading, which stays at the top.
    controller.showFile(at: 12)
    await controller.fileLoad?.value

    let row = table.selectedRow
    let heading = row - 3
    #expect(table.view(atColumn: 0, row: heading, makeIfNecessary: true) is FolderHeadingCell)
    let top = scrollView.contentView.bounds.minY + scrollView.contentInsets.top
    #expect(table.rect(ofRow: heading).minY < top, "The heading stays at the top")
    #expect(table.rect(ofRow: row).minY >= top + table.rect(ofRow: heading).height)
  }

  @Test func fileWithUnsavedChangesShowsADotAtTheEndOfItsRowAndVoiceOverSaysEdited() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let fileList = try #require(controller.collectionLayout?.fileList)

    fileList.changedPaths = ["Sources/Orders/Discount.swift"]

    let cell = try #require(
      fileList.tableView.view(atColumn: 0, row: 4, makeIfNecessary: true) as? FileListCell)
    cell.layoutSubtreeIfNeeded()
    #expect(cell.accessibilityLabel() == "Discount.swift, Sources/Orders, New, Edited")
    #expect(!cell.changedDot.isHidden)
    #expect(cell.changedDot.frame.maxX == cell.bounds.width - WindowMetrics.changedFileDotInset)
    #expect(try Self.labels(in: controller)[3] == "OrderService.swift, Sources/Orders, Modified")
  }

  @Test func dotStandsWhereItWouldInASidebarOfTheStandardWidthUnlessTheNamePushesIt()
    async throws
  {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    let layout = try #require(controller.collectionLayout)
    let table = layout.fileList.tableView
    layout.fileList.changedPaths = [
      "README.md",
      "Resources/Configuration/Environments/Production/prices-and-discounts-for-every-region.json",
    ]
    let cell = { (row: Int) throws -> FileListCell in
      let cell = try #require(
        table.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileListCell)
      cell.layoutSubtreeIfNeeded()
      return cell
    }
    // Where the text of the name ends; the frame of a label reaches a little beyond.
    let nameRect = { (cell: FileListCell) in cell.name.alignmentRect(forFrame: cell.name.frame) }
    let spacing = WindowMetrics.fileRowSpacing
    let end = WindowMetrics.changedFileDotInset

    let short = try cell(0)
    let long = try cell(6)
    #expect(short.changedDot.frame.maxX == short.bounds.width - end)
    #expect(long.changedDot.frame.maxX == long.bounds.width - end)
    #expect(nameRect(long).maxX <= long.changedDot.frame.minX - spacing)
    #expect(nameRect(long).width < long.name.intrinsicContentSize.width, "Shortened")

    layout.splitView.setPosition(WindowMetrics.maximumSidebarWidth, ofDividerAt: 0)
    layout.view.layoutSubtreeIfNeeded()

    let wideShort = try cell(0)
    let wideLong = try cell(6)
    #expect(wideShort.bounds.width > WindowMetrics.sidebarWidth)
    #expect(wideShort.changedDot.frame.maxX == WindowMetrics.sidebarWidth - end)
    #expect(nameRect(wideLong).width == wideLong.name.intrinsicContentSize.width)
    #expect(wideLong.changedDot.frame.minX == nameRect(wideLong).maxX + spacing)
  }
}

extension FileListViewController {
  /// The files the list shows, in the order it shows them.
  var listedFiles: [CollectedFile] {
    groups.order.map { files[$0] }
  }
}
