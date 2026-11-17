import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The search of a session window: one find bar below the panes, the order of Find Next in a
/// merge and a comparison, the panes it leaves out, the current block, the strokes in the
/// overview bars and what VoiceOver hears.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SearchWindowTests {
  /// A merge of four lines with "needle" in each: the first and the last unchanged, the second
  /// unchanged too, and a conflict on the third, whose preview in the result is never searched.
  private static func needleMerge() async throws -> Session {
    try await SampleMerges.merge(
      base: "needle one\nsame\nneedle base\ntail needle\n",
      a: "needle one\nsame\nneedle a\ntail needle\n",
      b: "needle one\nsame\nneedle b\ntail needle\n")
  }

  /// The pane and the row that the focus and the selection are in, as an expectation names
  /// them, such as "Base 2".
  private func place(in controller: SessionWindowController) throws -> String {
    let window = try #require(controller.window)
    let pane = try #require(
      Windows.panes(of: controller).first { window.firstResponder === $0.documentView })
    let row = pane.row(containingOffset: pane.documentView.selectedRange().location)
    return "\(name(of: pane, in: controller)) \(row)"
  }

  private func name(of pane: PaneView, in controller: SessionWindowController) -> String {
    if pane === controller.layout.resultPane { return "Result" }
    switch controller.presentation.role(of: pane) {
    case .a: return "A"
    case .base: return "Base"
    case .b: return "B"
    case nil: return "?"
    }
  }

  /// Opens the find bar, types `needle` and waits for `count` matches, then puts the focus at
  /// the start of the first pane, where Find Next goes on from.
  private func search(
    for needle: String, matches count: Int, with driver: SearchDriver
  ) async throws {
    #expect(try driver.send(.find))
    try driver.type(needle)
    await driver.waitForMatches(count: count)
    let first = try #require(driver.controller.presentation.searchedPanes.first)
    driver.controller.window?.makeFirstResponder(first.documentView)
    first.documentView.setSelectedRange(NSRange(location: 0, length: 0))
  }

  /// Sends Find Next `count` times and returns where each landed.
  private func findNext(
    _ count: Int, in controller: SessionWindowController, driver: SearchDriver
  ) throws -> [String] {
    try (0..<count).map { _ in
      #expect(try driver.send(.findNext))
      return try place(in: controller)
    }
  }

  @Test func findNextGoesBlockByBlockThroughABaseAndBThenTheResultAndSkipsThePreview()
    async throws
  {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      try await search(for: "needle", matches: 11, with: driver)
      try #require(controller.presentation.changes.blocks.count == 1)

      let places = try findNext(12, in: controller, driver: driver)

      #expect(
        places == [
          "A 0", "Base 0", "B 0", "Result 0", "A 2", "Base 2", "B 2", "A 3", "Base 3", "B 3",
          "Result 4", "A 0",
        ])
    }
  }

  @Test func jumpMakesTheBlockOfTheMatchCurrentAndOnlyThat() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      try await search(for: "needle", matches: 11, with: driver)
      controller.presentation.setCurrentBlock(nil)

      _ = try findNext(4, in: controller, driver: driver)
      #expect(controller.presentation.currentBlock == nil)
      _ = try findNext(1, in: controller, driver: driver)
      #expect(controller.presentation.currentBlock == 0)
      // A match outside every changed block leaves the current block as it is.
      _ = try findNext(3, in: controller, driver: driver)
      #expect(controller.presentation.currentBlock == 0)
    }
  }

  @Test func findNextInAComparisonGoesLeftThenRight() async throws {
    try await FindPasteboard.preserving {
      let session = try await SampleDiffs.diff(
        old: "needle\nkeep needle\nold needle\n", new: "needle\nkeep needle\nnew needle\n")
      let controller = try Windows.controller(for: session)
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      try await search(for: "needle", matches: 6, with: driver)

      let places = try findNext(6, in: controller, driver: driver)

      // The unchanged lines before the change are one block, as the change is.
      #expect(places == ["A 0", "A 1", "B 0", "B 1", "A 2", "B 2"])
      #expect(controller.presentation.currentBlock == 0)
    }
  }

  @Test func hiddenBaseIsNotSearchedAndAMaximizedResultIsSearchedAlone() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      controller.perform(.toggleBase)
      #expect(!controller.layout.showsBase)
      // Checked before waiting for the finder, which would wait in vain for the wrong count.
      let base = try #require(controller.layout.sourcePane(.base))
      try #require(!driver.search.sections.contains { $0.pane === base })
      try await search(for: "needle", matches: 8, with: driver)
      let withoutBase = try findNext(9, in: controller, driver: driver)
      #expect(
        withoutBase == ["A 0", "B 0", "Result 0", "A 2", "B 2", "A 3", "B 3", "Result 4", "A 0"])

      // Find searches anew what the panes show then.
      controller.perform(.toggleBase)
      #expect(try driver.send(.find))
      await driver.waitForMatches(count: 11)
      controller.perform(.toggleResultMaximized)
      #expect(controller.layout.maximizesResult)
      try #require(driver.search.sections.allSatisfy { $0.pane === controller.layout.resultPane })
      #expect(try driver.send(.find))
      await driver.waitForMatches(count: 2)
      let result = try #require(controller.layout.resultPane)
      window.makeFirstResponder(result.documentView)
      result.documentView.setSelectedRange(NSRange(location: 0, length: 0))
      let resultAlone = try findNext(3, in: controller, driver: driver)
      #expect(resultAlone == ["Result 0", "Result 4", "Result 0"])
    }
  }

  @Test func findBarOpensBelowThePanesAboveTheFooterAndTakesTheFocus() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let bar = driver.search.findBar
      #expect(bar.barHeight == 0)

      #expect(try driver.send(.find))
      window.contentView?.layoutSubtreeIfNeeded()

      #expect(bar.isFindBarVisible)
      #expect(bar.barHeight > 0)
      let content = controller.content.view
      let barFrame = content.convert(bar.bounds, from: bar)
      let panesFrame = content.convert(
        controller.layout.view.bounds, from: controller.layout.view)
      let footerFrame = content.convert(
        controller.content.footer.bounds, from: controller.content.footer)
      #expect(barFrame.width == content.bounds.width)
      #expect(barFrame.height == bar.barHeight)
      // The content view is not flipped: the panes stand above the bar, the footer below it.
      #expect(panesFrame.minY == barFrame.maxY)
      #expect(footerFrame.maxY == barFrame.minY)
      let field = try driver.searchField
      #expect((window.firstResponder as? NSText)?.delegate as? NSSearchField === field)
      // No pane has a find bar of its own.
      for pane in Windows.panes(of: controller) {
        #expect(pane.documentView.enclosingScrollView?.isFindBarVisible == false)
        #expect(pane.documentView.usesFindBar == false)
      }
    }
  }

  @Test func findAfterTheFocusFellToTheWindowOpensTheBarOfTheWindowAgain() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let a = try #require(controller.layout.sourcePane(.a))
      window.makeFirstResponder(a.documentView)
      #expect(try driver.send(.find))
      try driver.type("needle")
      await driver.waitForMatches(count: 11)

      // Escape closes the bar and hands the focus back to the pane it came from.
      let editor = try #require(window.firstResponder as? NSTextView)
      editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      #expect(!driver.search.findBar.isFindBarVisible)
      #expect(window.firstResponder === a.documentView)

      // With the focus on the window, Find still reaches the window and opens its bar.
      window.makeFirstResponder(nil)
      #expect(try driver.send(.find))
      #expect(driver.search.findBar.isFindBarVisible)
      let field = try driver.searchField
      #expect((window.firstResponder as? NSText)?.delegate as? NSSearchField === field)
      // Find Next from the field of the bar reaches the window too.
      #expect(try driver.send(.findNext))
    }
  }

  @Test func closingTheWindowEndsTheSearchRightAfterAJump() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      let driver = SearchDriver(controller)
      try await search(for: "needle", matches: 11, with: driver)
      #expect(try driver.send(.findNext))
      #expect(driver.search.validate(.nextMatch))

      window.close()

      // The finder lets go of the search: its indicator, which updates after a delay, finds
      // nothing left to ask once the window and the search are gone.
      #expect(!driver.search.validate(.nextMatch))
    }
  }

  @Test func findAndReplaceIsValidOnlyInAMergeAndLimitsTheSearchToTheResult() async throws {
    try await FindPasteboard.preserving {
      let diff = try Windows.controller(for: try await SampleDiffs.greeting())
      defer { diff.window?.close() }
      let merge = try Windows.controller(for: try await Self.needleMerge())
      defer { merge.window?.close() }
      let item = NSMenuItem(
        title: "", action: SessionCommand.findAndReplace.action, keyEquivalent: "")

      #expect(!diff.validateUserInterfaceItem(item))
      #expect(merge.validateUserInterfaceItem(item))

      let replaceAll = NSMenuItem(
        title: "", action: SessionCommand.replaceAll.action, keyEquivalent: "")
      #expect(!diff.validateUserInterfaceItem(replaceAll))
      #expect(!merge.validateUserInterfaceItem(replaceAll))

      let driver = SearchDriver(merge)
      #expect(try driver.send(.findAndReplace))
      #expect(driver.search.findBar.isFindBarVisible)
      #expect(!merge.validateUserInterfaceItem(replaceAll))
      try driver.type("needle")
      await driver.waitForMatches(count: 2)
      #expect(driver.search.matches.allSatisfy { $0.pane === merge.layout.resultPane })
      #expect(try driver.replaceField.isEditable)
      #expect(merge.validateUserInterfaceItem(replaceAll))
      try driver.type("needle x")
      await driver.waitForMatches(count: 0)
      #expect(!merge.validateUserInterfaceItem(replaceAll))
      try driver.type("needle")
      await driver.waitForMatches(count: 2)
      // The matches stay on the way to the field for replacing.
      try driver.typeReplacement("pin")
      #expect(driver.search.matches.count == 2)
      #expect(merge.validateUserInterfaceItem(replaceAll))

      // Find goes back to every pane, where nothing can be replaced.
      #expect(try driver.send(.find))
      await driver.waitForMatches(count: 11)
      #expect(!merge.validateUserInterfaceItem(replaceAll))
    }
  }

  @Test func switchingReplaceOffInTheBarSearchesAllPanesAndOnAgainTheResultAlone()
    async throws
  {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let replaceAll = NSMenuItem(
        title: "", action: SessionCommand.replaceAll.action, keyEquivalent: "")
      #expect(try driver.send(.findAndReplace))
      #expect(driver.search.showsReplaceField)
      let bar = try #require(driver.search.findBar.findBarView)
      let toggle = try #require(
        Self.views(in: bar).compactMap { $0 as? NSButton }.first {
          $0.title == "Replace" && !$0.isHiddenOrHasHiddenAncestor
        })

      // The checkbox of the bar, as the user clicks it.
      toggle.performClick(nil)

      #expect(!driver.search.showsReplaceField)
      // Checked before waiting for the finder, which would wait in vain for the wrong count.
      try #require(Self.searchesAllPanes(driver.search))
      try driver.type("needle")
      await driver.waitForMatches(count: 11)
      #expect(!controller.validateUserInterfaceItem(replaceAll))

      toggle.performClick(nil)

      #expect(driver.search.showsReplaceField)
      try #require(!Self.searchesAllPanes(driver.search))
      try driver.type("needle a")
      await driver.waitForMatches(count: 0)
      try driver.type("needle")
      await driver.waitForMatches(count: 2)
      #expect(driver.search.matches.allSatisfy { $0.pane === controller.layout.resultPane })
      #expect(controller.validateUserInterfaceItem(replaceAll))
    }
  }

  @Test func findAfterTheBarClosedWhileReplacingSearchesAllPanesWithoutTheFieldForReplacing()
    async throws
  {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      #expect(try driver.send(.findAndReplace))
      #expect(driver.search.showsReplaceField)
      // Done of the bar.
      driver.search.perform(.hideFindInterface)
      #expect(!driver.search.findBar.isFindBarVisible)

      #expect(try driver.send(.find))

      #expect(driver.search.findBar.isFindBarVisible)
      #expect(!driver.search.showsReplaceField)
      try #require(Self.searchesAllPanes(driver.search))
      try driver.type("needle")
      await driver.waitForMatches(count: 11)
    }
  }

  /// Whether `search` goes through all panes rather than the result alone.
  private static func searchesAllPanes(_ search: PaneSearch) -> Bool {
    if case .allPanes = search.scope { true } else { false }
  }

  private static func views(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(views(in:))
  }

  @Test func commandsOfTheSearchAreValidOnlyWhereTheyWork() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      defer { controller.window?.close() }
      let validate = { (command: SessionCommand) in
        controller.validateUserInterfaceItem(
          NSMenuItem(title: "", action: command.action, keyEquivalent: ""))
      }
      NSPasteboard(name: .find).clearContents()
      #expect(validate(.find))
      try await search(for: "needle", matches: 11, with: SearchDriver(controller))
      #expect(validate(.findNext))
      #expect(validate(.findPrevious))

      let unavailable = try Windows.controller(
        for: try await SampleDiffs.unavailable(isBinary: true).emptySession(),
        unavailable: SampleDiffs.unavailable(isBinary: true))
      defer { unavailable.window?.close() }
      for command in [SessionCommand.find, .findAndReplace, .findNext, .useSelectionForFind] {
        #expect(
          !unavailable.validateUserInterfaceItem(
            NSMenuItem(title: "", action: command.action, keyEquivalent: "")), "\(command)")
      }
    }
  }

  @Test func matchesOfConnectedSidesStandOnTheRowsOfTheGridInTheOverviewBar() async throws {
    try await FindPasteboard.preserving {
      // Two lines more at the top of the newer file: the needle is row 3 of the older file and
      // row 5 of the newer one, which is row 5 of the grid that the bar shows.
      let controller = try Windows.controller(
        for: try await SampleDiffs.diff(old: "a\nb\nc\nneedle\n", new: "x\ny\na\nb\nc\nneedle\n"))
      let window = try #require(controller.window)
      defer { window.close() }
      controller.perform(.showConnectedSides)
      #expect(!controller.presentation.alignsLines)
      let driver = SearchDriver(controller)
      #expect(try driver.send(.find))
      try driver.type("needle")
      await driver.waitForMatches(count: 2)

      #expect(driver.search.matches.map(\.row).sorted() == [3, 5])
      #expect(controller.presentation.sourcesOverviewBar.matchRows == IndexSet([5]))
    }
  }

  @Test func rowsOfMatchesOfPanesSideBySideJoinAsTheirUnion() {
    // The seed of the random rows, which a failure names.
    let seed: UInt64 = 0x0B5E_4A44
    var generator = SeededGenerator(seed: seed)
    for _ in 0..<20 {
      let sets = (0..<Int.random(in: 0...3, using: &generator)).map { _ in
        IndexSet(
          (0..<Int.random(in: 0..<200, using: &generator)).map { _ in
            Int.random(in: 0..<300, using: &generator)
          })
      }
      let expected = sets.reduce(IndexSet()) { $0.union($1) }
      #expect(SessionPresentation.union(of: sets) == expected, "seed \(seed)")
    }
  }

  @Test func matchesStandAsStrokesInTheOverviewBarsWhileTheBarIsOpen() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      #expect(try driver.send(.find))
      try driver.type("needle")
      await driver.waitForMatches(count: 11)

      let presentation = controller.presentation
      #expect(presentation.sourcesOverviewBar.matchRows == IndexSet([0, 2, 3]))
      #expect(presentation.resultOverviewBar?.matchRows == IndexSet([0, 4]))
      // The strokes stay while the focus goes from pane to pane with the matches.
      let a = try #require(controller.layout.sourcePane(.a))
      window.makeFirstResponder(a.documentView)
      a.documentView.setSelectedRange(NSRange(location: 1, length: 0))
      #expect(try driver.send(.findNext))
      #expect(window.firstResponder === controller.layout.sourcePane(.base)?.documentView)
      #expect(presentation.sourcesOverviewBar.matchRows == IndexSet([0, 2, 3]))
      #expect(presentation.resultOverviewBar?.matchRows == IndexSet([0, 4]))

      driver.search.perform(.hideFindInterface)
      #expect(presentation.sourcesOverviewBar.matchRows.isEmpty)
      #expect(presentation.resultOverviewBar?.matchRows.isEmpty == true)
    }
  }

  @Test func voiceOverHearsHowManyMatchesInHowManyPanes() async throws {
    #expect(
      SessionPresentation.matchesAnnouncement(matchCount: 12, paneCount: 3)
        == "12 matches in 3 panes")
    #expect(
      SessionPresentation.matchesAnnouncement(matchCount: 1, paneCount: 1) == "1 match in 1 pane")
    #expect(SessionPresentation.matchesAnnouncement(matchCount: 0, paneCount: 0) == "No matches")

    try await FindPasteboard.preserving {
      let controller = try Windows.controller(for: try await Self.needleMerge())
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      #expect(try driver.send(.find))
      try driver.type("needle a")
      await driver.waitForMatches(count: 1)
      #expect(driver.announcements.last == "1 match in 1 pane")
      try driver.type("needle b")
      await driver.waitForMatches(count: 2)
      #expect(driver.announcements.last == "2 matches in 2 panes")
      try driver.type("needle x")
      await driver.waitForMatches(count: 0)
      #expect(driver.announcements.last == "No matches")
    }
  }

  @Test func matchInACollapsedRunExpandsItAndThePanesFollow() async throws {
    try await FindPasteboard.preserving {
      let controller = try Windows.controller(
        for: try await SampleMerges.manyBlocks(lineCount: 300, spacing: 100))
      let window = try #require(controller.window)
      defer { window.close() }
      let driver = SearchDriver(controller)
      let presentation = controller.presentation
      let row = presentation.changes.session.rowLayout.row(ofLine: 60, in: .a)
      try #require(presentation.collapsed.run(containingRow: row) != nil)
      let a = try #require(controller.layout.sourcePane(.a))
      let b = try #require(controller.layout.sourcePane(.b))
      window.makeFirstResponder(a.documentView)
      a.documentView.setSelectedRange(NSRange(location: 0, length: 0))

      // The search as the user types shows the first match after the selection.
      #expect(try driver.send(.find))
      try driver.type("line 61")
      await driver.waitForMatches(count: 4)

      #expect(presentation.collapsed.run(containingRow: row) == nil)
      #expect(a.row(containingOffset: a.documentView.selectedRange().location) == row)
      #expect(Windows.scrollOffset(of: a) > 0)
      #expect(Windows.scrollOffset(of: b) == Windows.scrollOffset(of: a))
    }
  }
}

/// The rows the search goes through: every row of every pane it searches, once, and in a window
/// that compares several files, the rows of the file it shows.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SearchSectionTests {
  /// Records an issue unless the sections of `controller` go through every row of each pane
  /// they name once, in order within the pane, and the search has them.
  private func checkSections(
    of controller: SessionWindowController, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let presentation = controller.presentation
    let sections = presentation.searchSections
    for pane in presentation.searchedPanes {
      let rows = sections.filter { $0.pane === pane }.map(\.rows)
      #expect(
        rows.flatMap(\.self) == Array(0..<pane.content.lineNumbers.count),
        sourceLocation: sourceLocation)
    }
    #expect(
      sections.map { ObjectIdentifier($0.pane) }
        == presentation.search.sections.map { ObjectIdentifier($0.pane) },
      sourceLocation: sourceLocation)
    #expect(
      sections.map(\.rows) == presentation.search.sections.map(\.rows),
      sourceLocation: sourceLocation)
  }

  @Test func everyRowOfEveryPaneIsSearchedOnceAlsoAfterDecisionsAndTyping() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.example())
    defer { controller.window?.close() }
    checkSections(of: controller)
    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    controller.perform(.useAThenB)
    checkSections(of: controller)
    try controller.type("typed\nlines\n", over: 0..<0, with: .insertText)
    checkSections(of: controller)
    controller.perform(.showConnectedSides)
    checkSections(of: controller)
  }

  @Test func windowOfSeveralFilesSearchesTheFileItShows() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    checkSections(of: controller)
    let before = controller.presentation.search.sections.map(\.rows)

    controller.showNextFile(nil)
    await controller.fileLoad?.value

    checkSections(of: controller)
    #expect(controller.presentation.search.sections.map(\.rows) != before)
    #expect(controller.canPerform(.find))
    #expect(!controller.canPerform(.findAndReplace))
  }
}
