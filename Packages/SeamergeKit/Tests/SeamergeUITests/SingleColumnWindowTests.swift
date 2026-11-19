import AppKit
import MergeModel
import SwiftUI
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// A comparison in a single column: one pane with both files below one header, the switch to it
/// and back keeping the current block, the block at the reading line and the selection, which
/// commands act there and which do not, and the search, the jumps, collapsing, wrapping and Swap
/// Sides on the rows of the column.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct SingleColumnWindowTests {
  @Test func singleColumnShowsBothFilesInOnePaneBelowOneHeaderWithBothNames() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    #expect(column.isShown)
    #expect(controller.layout.sourcePanes.allSatisfy { !$0.pane.isShown })
    let session = controller.presentation.changes.session
    let layout = SingleColumnLayout(session: session)
    #expect(column.content.text == layout.displayText.string)
    let numbers = try #require(column.content.sideLineNumbers)
    let places = (0..<layout.rowCount).map(layout.place(atRow:))
    #expect(numbers.left == places.map { Int32($0.line(in: .a) ?? -1) })
    #expect(numbers.right == places.map { Int32($0.line(in: .b) ?? -1) })

    // An insertion, a change and a removal: the change has a part for each side.
    let blocks = column.content.blocks
    #expect(blocks.map(\.style) == [.tinted(.b), .tinted(.a), .tinted(.a)])
    #expect(blocks.map { $0.lowerPart?.style } == [nil, .tinted(.b), nil])
    #expect(blocks.map(\.marker) == [.added, .changed, .removed])

    let header = try #require(Self.columnHeader(of: controller))
    #expect(header.rootView.headers.map(\.role) == [.a, .b])
    let names = try [Role.a, .b].map { try #require(controller.presentation.headers[$0]) }
    #expect(header.rootView.spokenName == "\(names[0].spokenName) to \(names[1].spokenName)")
  }

  @Test(arguments: [true, false])
  func switchingKeepsTheCurrentBlockAndTheBlockAtTheReadingLine(alignsLines: Bool) async throws {
    let settings = UserSettings.private()
    settings.alignsLines = alignsLines
    let controller = try Windows.controller(
      for: try await SampleDiffs.everyKindOfChange(), settings: settings)
    let presentation = controller.presentation
    for _ in 0..<20 {
      controller.selectNextChange(nil)
    }
    let current = try #require(presentation.currentBlock)
    let block = presentation.changes.blocks[current]
    #expect(try Self.blockAtReadingLine(of: controller) == block.id)

    controller.showSingleColumn(nil)
    #expect(presentation.currentBlock == current)
    #expect(try Self.blockAtReadingLine(of: controller) == block.id)
    let column = try #require(controller.layout.columnPane)
    #expect(column.currentBlock == current)

    // The second part of the block at the reading line, then back to the panes side by side.
    let lowerRow = try #require(column.content.blocks[current].lowerPart?.firstRow)
    column.scroll(toPlaceRowAtReadingLine: lowerRow + 1, motion: .cut)
    controller.show(alignsLines ? .aligned : .connected)
    #expect(presentation.alignsLines == alignsLines)
    #expect(presentation.currentBlock == current)
    #expect(try Self.blockAtReadingLine(of: controller) == block.id)
  }

  @Test func unchangedLineAtTheReadingLineStaysThereOnTheGrid() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    let layout = try #require(controller.presentation.columnLayout)
    let row = try #require((200..<layout.rowCount).first { layout.place(atRow: $0).side == nil })
    column.scroll(toPlaceRowAtReadingLine: row, fraction: 0.5, motion: .cut)
    let line = try #require(layout.place(atRow: row).line(in: .b))

    controller.showAlignedLines(nil)
    let b = try #require(controller.layout.sourcePane(.b))
    let gridRow = b.rowAtReadingLine.row
    #expect(controller.presentation.changes.session.rowLayout.line(atRow: gridRow, in: .b) == line)
  }

  @Test func selectionOfThePaneWithTheFocusGoesIntoTheColumnAndBack() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let window = try #require(controller.window)
    let a = try #require(controller.layout.sourcePane(.a))
    // The removed function of A, from its name to the end of its next line.
    let text = a.documentView.string as NSString
    let start = text.range(of: "farewell").location
    let selected = NSRange(location: start, length: text.range(of: "Goodbye").location - start)
    window.makeFirstResponder(a.documentView)
    a.documentView.setSelectedRange(selected)
    let selectedText = text.substring(with: selected)

    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    #expect(window.firstResponder === column.documentView)
    let columnText = column.documentView.string as NSString
    #expect(columnText.substring(with: column.documentView.selectedRange()) == selectedText)

    controller.showAlignedLines(nil)
    #expect(window.firstResponder === a.documentView)
    #expect(text.substring(with: a.documentView.selectedRange()) == selectedText)
  }

  @Test func commandsActWhereTheyHaveAnEffectInAComparisonInItsColumnAndInAMerge() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    let items = LineArrangement.allCases.map { Self.menuItem($0.command) }
    let sync = Self.menuItem(.toggleScrollSynchronization)
    #expect(items.allSatisfy { controller.validateUserInterfaceItem($0) })
    #expect(items.map(\.state) == [.on, .off, .off])
    #expect(controller.validateUserInterfaceItem(sync) && sync.state == .on)

    controller.showSingleColumn(nil)
    // One arrangement checked, and each of them can be chosen.
    #expect(items.allSatisfy { controller.validateUserInterfaceItem($0) })
    #expect(items.map(\.state) == [.off, .off, .on])
    // Disabled, and still checked: the panes side by side get it back as it was.
    #expect(!controller.validateUserInterfaceItem(sync) && sync.state == .on)
    controller.toggleScrollSynchronization(nil)
    #expect(controller.presentation.scrollSync.isEnabled)
    for command in [
      SessionCommand.nextChange, .lastChange, .find, .toggleLineWrapping, .toggleInvisibles,
      .swapSides, .showAllLines, .goToLine, .copyBlock, .copyPatch, .zoomIn,
    ] {
      #expect(controller.canPerform(command), "\(command)")
    }
    let footer = controller.content.footer
    let syncToggle = try #require(footer.button(of: .scrollSynchronization))
    #expect(!syncToggle.isEnabled && syncToggle.state == .on)
    #expect(syncToggle.toolTip == "Synchronize scrolling (a single column scrolls alone)")

    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(!merge.validateUserInterfaceItem(items[2]) && items[2].state == .off)
    merge.showSingleColumn(nil)
    #expect(merge.layout.columnPane == nil)
    #expect(merge.presentation.lineArrangement == .aligned)
    let key = try #require(SessionCommand.showSingleColumn.keyEquivalent(in: .diff))
    #expect(key.key == "u" && key.modifiers == [.option, .command])
    #expect(SessionCommand.groups(in: .view)[1] == LineArrangement.allCases.map(\.command))
  }

  @Test func toolbarChoosesTheArrangementAndFollowsTheMenu() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let choice = try Self.arrangementChoice(of: controller)
    let names = ["Aligned Lines", "Connected Sides", "Single Column"]
    #expect(choice.subitems.map(\.label) == names)
    #expect(choice.subitems.map { $0.image?.accessibilityDescription } == names)
    // The words of the View menu, for the same arrangements.
    #expect(LineArrangement.allCases.map(\.command.title) == names)
    #expect(choice.subitems.map(\.toolTip) == LineArrangement.allCases.map(\.command.help))
    #expect(choice.subitems.allSatisfy { ($0.toolTip?.count ?? 0) > 0 })
    #expect(choice.subitems.allSatisfy { $0.toolTip.map { $0.count <= 75 } ?? false })
    #expect(choice.selectionMode == .selectOne)
    #expect(choice.selectedIndex == 0)

    controller.showSingleColumn(nil)
    #expect(choice.selectedIndex == 2)
    #expect(choice.subitems.allSatisfy { $0.isEnabled })
    controller.showAlignedLines(nil)
    #expect(choice.selectedIndex == 0)
    controller.showConnectedSides(nil)
    #expect(choice.selectedIndex == 1)

    choice.selectedIndex = 2
    controller.chooseLineArrangement(choice)
    #expect(controller.presentation.lineArrangement == .singleColumn)
    // Choosing Aligned leaves the column and lines up the panes side by side.
    choice.selectedIndex = 0
    controller.chooseLineArrangement(choice)
    #expect(controller.presentation.lineArrangement == .aligned)
    #expect(choice.selectedIndex == 0)

    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    let mergeChoice = try Self.arrangementChoice(of: merge)
    #expect(mergeChoice.subitems.map(\.label) == ["Aligned Lines", "Connected Sides"])

    let unavailable = SampleDiffs.unavailable(isBinary: true)
    let nothing = try Windows.controller(
      for: try await unavailable.emptySession(), unavailable: unavailable)
    #expect(try Self.arrangementChoice(of: nothing).subitems.allSatisfy { !$0.isEnabled })
    #expect(!nothing.canPerform(.showSingleColumn))
  }

  @Test func savedToolbarWithoutTheChoiceGetsItOnceAndKeepsTheRest() throws {
    let settings = UserSettings.private()
    let sessionToolbar = SessionToolbar(kind: .diff, doneStyle: .standard)
    let toolbar = sessionToolbar.toolbar
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.titled],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.toolbar = toolbar
    // Toolbars of one identifier share their configuration; this one gives it back at the end.
    let original = toolbar.itemIdentifiers
    defer { toolbar.itemIdentifiers = original }
    while let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .lineArrangement }) {
      toolbar.removeItem(at: index)
    }
    toolbar.insertItem(withItemIdentifier: .comparison, at: 0)
    let saved = toolbar.items.map(\.itemIdentifier)

    sessionToolbar.insertArrangementOnce(rememberingIn: settings)
    #expect(toolbar.items.map(\.itemIdentifier) == saved + [.lineArrangement])
    #expect(settings.toolbarsWithArrangement == [toolbar.identifier])

    toolbar.removeItem(at: toolbar.items.count - 1)
    sessionToolbar.insertArrangementOnce(rememberingIn: settings)
    #expect(toolbar.items.map(\.itemIdentifier) == saved)
    let reread = UserSettings(defaults: settings.defaults)
    #expect(reread.toolbarsWithArrangement == [toolbar.identifier])
  }

  @Test func searchGoesThroughTheRowsOfTheColumnOnce() async throws {
    try await FindPasteboard.preserving {
      let session = try await SampleDiffs.diff(
        old: "needle shared\nneedle old\nsame\nneedle tail\n",
        new: "needle shared\nneedle new\nsame\nneedle tail\n")
      let controller = try Windows.controller(for: session)
      let window = try #require(controller.window)
      defer { window.close() }
      controller.showSingleColumn(nil)
      let column = try #require(controller.layout.columnPane)
      #expect(controller.presentation.searchedPanes.map { $0 === column } == [true])
      let driver = SearchDriver(controller)
      #expect(try driver.send(.find))
      try driver.type("needle")
      await driver.waitForMatches(count: 4)
      #expect(driver.search.matches.allSatisfy { $0.pane === column })
      #expect(controller.presentation.columnOverviewBar?.matchRows == IndexSet([0, 1, 2, 4]))
      window.makeFirstResponder(column.documentView)
      column.documentView.setSelectedRange(NSRange(location: 0, length: 0))
      var rows: [Int] = []
      for _ in 0..<4 {
        #expect(try driver.send(.findNext))
        rows.append(column.row(containingOffset: column.documentView.selectedRange().location))
      }
      #expect(rows == [0, 1, 2, 4])
      #expect(controller.presentation.currentBlock == 0)
    }
  }

  @Test func jumpsAndTheArrowOfAMoveWorkOnTheRowsOfTheColumn() async throws {
    let controller = try Windows.controller(for: try await MoveSamples.movedDown())
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    let moves = column.content.blocks.indices.filter { column.content.blocks[$0].move != nil }
    #expect(moves.count == 2)
    let (source, destination) = (moves[0], moves[1])
    #expect(column.content.blocks[source].move?.otherBlock == destination)
    #expect(column.content.blocks[destination].move?.otherBlock == source)

    controller.presentation.jump(to: source)
    let gutter = try #require(
      column.subviews.first { $0.accessibilityLabel() == "Change markers" })
    let elements = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    let arrow = try #require(elements.first { $0.accessibilityRole() == .button })
    #expect(arrow.accessibilityLabel() == "Moved to line 15")
    // The rows of the column stay elements of their own beside the arrow.
    #expect(elements.contains { $0.accessibilityLabel() == "Removed" })

    controller.goToOtherEndOfMove(nil)
    #expect(controller.presentation.currentBlock == destination)
    #expect(column.showsWhole(rows: column.content.blocks[destination].rows))

    controller.selectFirstChange(nil)
    #expect(controller.presentation.currentBlock == 0)
    #expect(column.showsWhole(rows: column.content.blocks[0].rows))
  }

  @Test func collapsingWrappingAndSwapSidesActOnTheColumn() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.manyChanges())
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    let a = try #require(controller.layout.sourcePane(.a))
    let runs = column.collapsedRuns
    #expect(!runs.isEmpty && runs.count == a.collapsedRuns.count)
    controller.presentation.pane(column, didAskToExpand: runs[1])
    #expect(column.collapsedRuns.count == runs.count - 1)
    #expect(a.collapsedRuns.count == runs.count - 1)
    controller.collapseUnchangedLines(nil)
    #expect(column.collapsedRuns == runs)

    controller.toggleLineWrapping(nil)
    #expect(column.wrapsLines)
    controller.toggleInvisibles(nil)
    #expect(column.showsInvisibles)

    controller.selectNextChange(nil)
    let current = try #require(controller.presentation.currentBlock)
    controller.swapSides(nil)
    #expect(controller.presentation.columnLayout?.firstSide == .b)
    #expect(controller.presentation.currentBlock == current)
    #expect(column.currentBlock == current)
    #expect(column.content.blocks[current].style == .tinted(.b))
    #expect(column.content.blocks[current].lowerPart?.style == .tinted(.a))
    let header = try #require(Self.columnHeader(of: controller))
    #expect(header.rootView.headers.map(\.role) == [.b, .a])
  }

  @Test func settingsCanStartAComparisonInASingleColumnButNotAMerge() async throws {
    let settings = UserSettings.private()
    settings.showsSingleColumn = true
    settings.alignsLines = false
    let comparison = try Windows.controller(
      for: try await SampleDiffs.greeting(), settings: settings)
    let column = try #require(comparison.layout.columnPane)
    #expect(comparison.presentation.lineArrangement == .singleColumn)
    #expect(comparison.window?.firstResponder === column.documentView)
    #expect(!comparison.presentation.alignsLines)

    let merge = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    #expect(merge.presentation.lineArrangement == .connected)
    #expect(UserSettings(defaults: settings.defaults).showsSingleColumn)
  }

  @Test func windowOfSeveralFilesKeepsItsColumnFromFileToFile() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    let window = try #require(controller.window)
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    controller.selectNextChange(nil)
    let firstBlock = controller.presentation.currentBlock

    while controller.canPerform(.nextFile) {
      #expect(window.tryToPerform(SessionCommand.nextFile.action, with: nil))
      await controller.fileLoad?.value
      #expect(controller.presentation.lineArrangement == .singleColumn)
      #expect(column.isShown)
      let session = controller.presentation.changes.session
      #expect(column.content.text == SingleColumnLayout(session: session).displayText.string)
      let header = try #require(Self.columnHeader(of: controller))
      #expect(
        header.rootView.headers.map(\.name)
          == [Role.a, .b].map { controller.presentation.headers[$0]?.name })
    }
    while controller.canPerform(.previousFile) {
      #expect(window.tryToPerform(SessionCommand.previousFile.action, with: nil))
      await controller.fileLoad?.value
    }
    #expect(controller.presentation.currentBlock == firstBlock)
    #expect(column.isShown)
  }

  @Test func columnShowsTheFilesAnewAndTheIgnoredPlaces() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(
        old: "let a = 1\nlet b  = 2\nold\n", new: "let a = 1\nlet b = 2\nnew\n",
        mode: .ignoreWhitespaceAmount))
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    #expect(column.content.ignoredDifferenceRows == IndexSet(integer: 1))
    #expect(column.content.ignoredDifferencePlaces.isEmpty)
    controller.toggleIgnoredChanges(nil)
    #expect(!column.content.ignoredDifferencePlaces.isEmpty)

    let other = try await SampleDiffs.diff(old: "one\ntwo\n", new: "one\nthree\n")
    controller.presentation.show(other, result: nil)
    #expect(column.content.text == SingleColumnLayout(session: other).displayText.string)
    #expect(controller.presentation.lineArrangement == .singleColumn)
  }

  @Test func comparisonThatCannotBeShownSaysWhyInPlaceOfTheColumn() async throws {
    let settings = UserSettings.private()
    settings.showsSingleColumn = true
    let unavailable = SampleDiffs.unavailable(isBinary: true)
    let controller = try Windows.controller(
      for: try await unavailable.emptySession(), unavailable: unavailable, settings: settings)
    let column = try #require(controller.layout.columnPane)
    #expect(column.isHidden)
    let root = try #require(controller.window?.contentView)
    #expect(Self.descendants(of: root).contains { $0 is UnavailableComparisonView })
    #expect(LineArrangement.allCases.allSatisfy { !controller.canShow($0) })
  }

  @Test func columnNeedsTheRoomOfOnePane() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let sideBySide = controller.layout.minimumWidth
    controller.showSingleColumn(nil)
    let column = try #require(controller.layout.columnPane)
    #expect(controller.layout.minimumWidth == column.minimumWidth)
    #expect(controller.layout.minimumWidth < sideBySide)
  }

  @Test func switchingABigComparisonTakesLessThanATenthOfASecond() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "big" })
    let (merge, _) = try await scenario.load()
    let session = try await Session.diff(
      old: try #require(merge.file(for: .base)), new: try #require(merge.file(for: .b)),
      mode: .windowDefault)
    let controller = try Windows.controller(for: session)
    let clock = ContinuousClock()
    var times: [Duration] = []
    for _ in 0..<2 {
      times.append(clock.measure { controller.showSingleColumn(nil) })
      times.append(clock.measure { controller.showAlignedLines(nil) })
    }
    try Rendering.write(
      text: "single column of big: " + times.map { "\($0)" }.joined(separator: ", "),
      named: "single-column-timing")
    #if DEBUG
      // Unoptimized code takes several times as long; the tenth of a second holds for an
      // optimized build, as `swift test -c release -Xswiftc -enable-testing` shows.
      let limit = Duration.milliseconds(400)
    #else
      let limit = Duration.milliseconds(100)
    #endif
    #expect(times.allSatisfy { $0 < limit }, "\(times)")
  }

  /// The block of the session at the reading line of the window: of the single column, or of
  /// the panes side by side.
  private static func blockAtReadingLine(of controller: SessionWindowController) throws -> Int {
    let presentation = controller.presentation
    if let layout = presentation.columnLayout, let column = controller.layout.columnPane {
      return layout.place(atRow: column.rowAtReadingLine.row).block.id
    }
    let place = try #require(presentation.gridPlaceAtReadingLine)
    return presentation.changes.session.rowLayout.block(atRow: Int(place)).id
  }

  /// The header above the single column of the window.
  private static func columnHeader(
    of controller: SessionWindowController
  ) -> HeaderHostingView<ColumnHeaderView>? {
    guard let root = controller.window?.contentView?.superview else { return nil }
    return descendants(of: root).lazy.compactMap { $0 as? HeaderHostingView<ColumnHeaderView> }
      .first
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
  }

  /// The choice of the arrangement in the toolbar of the window.
  private static func arrangementChoice(
    of controller: SessionWindowController
  ) throws -> NSToolbarItemGroup {
    try #require(
      controller.window?.toolbar?.items.first { $0.itemIdentifier == .lineArrangement }
        as? NSToolbarItemGroup)
  }

  private static func menuItem(_ command: SessionCommand) -> NSMenuItem {
    NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
  }
}
