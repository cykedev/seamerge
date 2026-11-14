import AppKit
import GitSupport
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The window of a comparison of two files: the same window as a merge, put together from two
/// panes without a result, with a toolbar that counts changes, commands that act without a
/// merge, the outcome Git expects, and Swap Sides.
@MainActor
@Suite struct DiffWindowTests {
  @Test func comparisonShowsTwoPanesSideBySideAndNothingBelow() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())

    #expect(controller.layout.sourcePanes.map(\.role) == [.a, .b])
    #expect(controller.layout.resultPane == nil)
    #expect(controller.layout.splitViewItems.count == 1)
    #expect(controller.presentation.result == nil)
    #expect(controller.presentation.decisionColumn == nil)
    #expect(controller.presentation.resultOverviewBar == nil)
    #expect(
      controller.layout.sourcePane(.b)?.overviewBar === controller.presentation.sourcesOverviewBar)
  }

  @Test func eachKindOfChangeIsTintedInTheColorOfItsSideWithItsMarker() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let (left, right) = try panes(of: controller)

    #expect(left.content.blocks.map(\.marker) == [nil, .changed, .removed])
    #expect(right.content.blocks.map(\.marker) == [.added, .changed, nil])
    #expect(left.content.blocks.allSatisfy { $0.style == .tinted(.a) })
    #expect(right.content.blocks.allSatisfy { $0.style == .tinted(.b) })
    // Red stands for what is open, and a comparison leaves nothing open.
    #expect((left.content.blocks + right.content.blocks).allSatisfy { $0.conflict == nil })
  }

  @Test func changedLineIsHighlightedLeftAgainstRightInBothPanesAndAfterTheSwap() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let (left, right) = try panes(of: controller)
    // The left side lacks the condition, marked where it is missing, and ends differently.
    let expected = (
      left: ["", #")!""#],
      right: [#"isFormal ? "Good day, \(name)\(punctuation)" : "#, #")\(punctuation)""#]
    )

    let before = (
      left: try highlightedText(ofBlock: 1, in: left),
      right: try highlightedText(ofBlock: 1, in: right)
    )
    #expect(before.left == expected.left)
    #expect(before.right == expected.right)

    controller.swapSides(nil)

    let after = (
      left: try highlightedText(ofBlock: 1, in: left),
      right: try highlightedText(ofBlock: 1, in: right)
    )
    #expect(after.left == expected.right)
    #expect(after.right == expected.left)
  }

  @Test func toolbarSaysWhichChangeIsCurrentBetweenItsArrows() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let toolbar = controller.toolbar
    let items = try toolbarItems(of: controller)
    let navigation = try #require(items[.changeNavigation] as? NSToolbarItemGroup)
    let (previous, next) = (navigation.subitems[0], navigation.subitems[1])

    #expect(
      toolbar.toolbarDefaultItemIdentifiers(toolbar.toolbar) == [.changeCount, .changeNavigation])
    #expect(toolbar.toolbar.centeredItemIdentifiers == [.changeCount, .changeNavigation])
    #expect(items[.done] == nil)
    #expect(items[.conflictCount] == nil)
    #expect(countLabel(of: controller) == "Change 1 of 3")
    #expect(previous.action == SessionCommand.previousChange.action)
    #expect(next.action == SessionCommand.nextChange.action)
    #expect(!previous.isEnabled)
    #expect(next.isEnabled)

    controller.selectLastChange(nil)

    #expect(countLabel(of: controller) == "Change 3 of 3")
    #expect(previous.isEnabled)
    #expect(!next.isEnabled)
  }

  @Test func countSaysWhichChangeIsCurrentOrHowManyThereAre() {
    #expect(SessionToolbar.countText(currentChange: 3, changeCount: 12) == "Change 4 of 12")
    #expect(SessionToolbar.countText(currentChange: nil, changeCount: 12) == "12 Changes")
    #expect(SessionToolbar.countText(currentChange: nil, changeCount: 1) == "1 Change")
    #expect(SessionToolbar.countText(currentChange: nil, changeCount: 0) == "No Changes")
  }

  @Test func optionCommandDownArrowGoesFromChangeToChange() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    let menu = NSMenu()
    for command in [SessionCommand.nextChange, .previousChange] {
      let keys = try #require(command.keyEquivalent(in: .diff))
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: keys.key)
      item.keyEquivalentModifierMask = keys.modifiers
      item.target = controller
      menu.addItem(item)
    }
    let window = try #require(controller.window)
    func press(_ arrow: String) throws -> Bool {
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [.option, .command], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: arrow,
          charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 0))
      return menu.performKeyEquivalent(with: event)
    }

    #expect(controller.presentation.currentBlock == 0)
    #expect(try press(SessionCommand.downArrow))
    #expect(controller.presentation.currentBlock == 1)
    #expect(try press(SessionCommand.downArrow))
    #expect(controller.presentation.currentBlock == 2)
    #expect(try press(SessionCommand.upArrow))
    #expect(controller.presentation.currentBlock == 1)
  }

  @Test func noCommandOfAMergeIsValidInAComparison() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())

    for command in [SessionCommand.nextConflict, .previousConflict, .toggleBase] {
      #expect(!controller.canPerform(command), "\(command)")
    }
    #expect(!controller.canPerform(.toggleResultMaximized))
    #expect(controller.canPerform(.nextChange))
    #expect(controller.canPerform(.swapSides))
    #expect(controller.canPerform(.showAllLines) == false)
    #expect(controller.canPerform(.collapseUnchangedLines) == false)
    let item = NSMenuItem(
      title: "", action: SessionCommand.toggleResultMaximized.action, keyEquivalent: "")
    #expect(!controller.validateUserInterfaceItem(item))
    // Both sides are read-only, so Return leaves the focus where it is.
    let first = controller.window?.firstResponder
    controller.enterTextMode()
    #expect(controller.window?.firstResponder === first)
    #expect(!controller.isInTextMode)
  }

  @Test func closingReportsSavedSoThatGitGoesOnToTheNextFile() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }

    controller.close()

    #expect(outcomes == [.saved])
  }

  @Test func skipRemainingFilesReportsCancelledOnceAndCloses() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }
    controller.showWindow(nil)

    controller.skipRemainingFiles(nil)

    #expect(outcomes == [.cancelled])
    #expect(controller.window?.isVisible == false)
  }

  @Test func cancellingReportsCancelledAsWhenTheAppQuits() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }

    controller.cancel()

    #expect(outcomes == [.cancelled])
  }

  @Test func skipRemainingFilesNeedsGitAndAFileAfterThisOne() async throws {
    let session = try await SampleDiffs.greeting()
    func canSkip(_ position: FilePosition?, git: Bool = true) throws -> Bool {
      let context = SessionContext(
        difftool: git
          ? DifftoolContext(path: "Sources/Greeting.swift", filePosition: position) : nil)
      return try Windows.controller(for: session, context: context).canPerform(.skipRemainingFiles)
    }

    #expect(try canSkip(FilePosition(number: 3, count: 12)))
    #expect(try canSkip(nil))
    #expect(try !canSkip(FilePosition(number: 12, count: 12)))
    #expect(try !canSkip(nil, git: false))
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(!merge.canPerform(.skipRemainingFiles))
  }

  @Test func windowIsTitledAfterThePathInTheRepositoryWithItsPlaceInTheRunOfGit() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    let window = try #require(controller.window)

    #expect(window.title == "Sources/Greeting.swift")
    #expect(window.subtitle == "File 3 of 12")
    let labels = controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() }
    #expect(
      labels == [
        "A, Sources/Greeting.swift, Earlier Version", "B, Sources/Greeting.swift, Working Copy",
      ])
  }

  @Test func windowOfTwoFilesWithoutGitIsTitledAfterBoth() async throws {
    let session = try await Session.diff(
      old: SourceFile(bytes: Data("a\n".utf8), label: "old.txt"),
      new: SourceFile(bytes: Data("b\n".utf8), label: "new.txt"), mode: .windowDefault)
    let controller = try Windows.controller(for: session)

    #expect(controller.window?.title == "old.txt ↔ new.txt")
    #expect(controller.window?.subtitle == "")
  }

  @Test func openInEditorOpensTheSideThatIsTheWorkingCopy() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "DiffWindowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let before = folder.appending(path: "Greeting_LEFT.swift")
    let workingCopy = folder.appending(path: "Greeting.swift")
    try Data(SampleDiffs.greetingOld.utf8).write(to: before)
    try Data(SampleDiffs.greetingNew.utf8).write(to: workingCopy)
    let session = try await Session.loadDiff(
      old: SessionFile(url: before, label: "Greeting.swift"),
      new: SessionFile(url: workingCopy, label: "Greeting.swift"))
    let workspace = WorkspaceRecorder()

    let withGit = try Windows.controller(
      for: session, context: SampleDiffs.gitContext, workspace: workspace)
    #expect(withGit.canPerform(.openInEditor))
    withGit.openInEditor(nil)
    #expect(workspace.openedURLs == [workingCopy])
    let withoutGit = try Windows.controller(for: session)
    #expect(!withoutGit.canPerform(.openInEditor))
  }

  @Test(arguments: [
    ComparisonMode.exact, .ignoreLineEndings, .ignoreWhitespaceAmount, .ignoreAllWhitespace,
  ])
  func everyComparisonModeCanBeChosen(mode: ComparisonMode) async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(
        old: SampleDiffs.reformattedOld, new: SampleDiffs.reformattedNew, mode: .exact))

    await controller.switchComparison(to: ComparisonOptions(mode: mode))

    #expect(controller.comparisonOptions.mode == mode)
    #expect(controller.presentation.changes.session.kind == .diff)
    let command = try #require(SessionCommand.allCases.first { $0.comparisonMode == mode })
    let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
    #expect(controller.validateUserInterfaceItem(item))
    #expect(item.state == .on)
  }

  @Test func reformattedFileHasNoChangesWhenAllWhitespaceIsIgnoredAndRingsWhereItDiffers()
    async throws
  {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(
        old: SampleDiffs.reformattedOld, new: SampleDiffs.reformattedNew))
    #expect(!controller.presentation.changes.blocks.isEmpty)

    await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))

    #expect(controller.presentation.changes.blocks.isEmpty)
    #expect(countLabel(of: controller) == "No Changes")
    #expect(try toolbarItems(of: controller)[.changeNavigation]?.isHidden == true)
    let (left, right) = try panes(of: controller)
    #expect(left.content.ignoredDifferenceRows == IndexSet([0, 1]))
    #expect(right.content.ignoredDifferenceRows == IndexSet([0, 1]))
  }

  @Test func swapSidesTurnsAnInsertionIntoARemovalWithHeadersAndColors() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.greeting(), context: SampleDiffs.gitContext)
    let (left, right) = try panes(of: controller)

    controller.swapSides(nil)

    #expect(controller.layout.sourcePanes.map(\.role) == [.b, .a])
    #expect(controller.layout.sourcePanes.map(\.pane) == [left, right])
    #expect(left.content.blocks.map(\.marker) == [.removed, .changed, nil])
    #expect(right.content.blocks.map(\.marker) == [nil, .changed, .added])
    #expect(left.content.blocks.allSatisfy { $0.style == .tinted(.b) })
    #expect(right.content.blocks.allSatisfy { $0.style == .tinted(.a) })
    #expect(left.accessibilityLabel()?.hasPrefix("B, ") == true)
    #expect(right.accessibilityLabel()?.hasPrefix("A, ") == true)
    let leading = controller.presentation.sourcesOverviewBar.marks.filter {
      $0.placement == .leading
    }
    #expect(!leading.isEmpty)
    #expect(leading.allSatisfy { $0.style == .tinted(.b) })
  }

  @Test func swapSidesKeepsTheCurrentChangeAndThePlaceAndTwiceIsTheStart() async throws {
    let undoManager = UndoManager()
    let controller = try Windows.controller(
      for: try await SampleDiffs.manyChanges(), undoManager: undoManager)
    let (left, right) = try panes(of: controller)
    controller.presentation.jump(to: 5)
    let offsets = [left, right].map(Windows.scrollOffset(of:))
    let contents = [left, right].map(\.content)
    #expect(offsets[0] > 0)

    controller.swapSides(nil)

    #expect(controller.presentation.currentBlock == 5)
    #expect([left, right].map(\.currentBlock) == [5, 5])
    #expect([left, right].map(Windows.scrollOffset(of:)) == offsets)
    #expect(left.content.text == contents[1].text)
    #expect(!undoManager.canUndo)

    controller.swapSides(nil)

    #expect(controller.layout.sourcePanes.map(\.role) == [.a, .b])
    #expect([left, right].map(\.content.text) == contents.map(\.text))
    #expect([left, right].map(\.content.blocks) == contents.map(\.blocks))
    #expect([left, right].map(Windows.scrollOffset(of:)) == offsets)
    #expect(controller.presentation.currentBlock == 5)
  }

  @Test(arguments: [true, false])
  func comparisonThatCannotBeShownSaysWhyAndOnlyCloses(isBinary: Bool) async throws {
    let unavailable = SampleDiffs.unavailable(isBinary: isBinary)
    let context = SessionContext(
      difftool: DifftoolContext(
        path: "Assets/logo.png", leftRole: .before, rightRole: .workingCopy,
        filePosition: FilePosition(number: 3, count: 12)))
    let controller = try Windows.controller(
      for: try await unavailable.emptySession(), context: context, unavailable: unavailable)
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }
    let window = try #require(controller.window)

    #expect(window.title == "Assets/logo.png")
    #expect(unavailable.title == "Seamerge can’t show the differences of “logo.png”")
    let reason =
      isBinary
      ? "“logo.png” isn’t a text file. Open it in the app that made it."
      : "Seamerge can’t read “logo.png”. Check that it exists and that you may read it."
    #expect(unavailable.message(in: SessionContext()) == reason)
    #expect(
      unavailable.message(in: SampleDiffs.gitContext)
        == reason + " Close the window to go on to the next file.")
    #expect(controller.layout.sourcePanes.allSatisfy { $0.pane.isHidden })
    let labels = controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() }
    #expect(
      labels == ["A, Assets/logo.png, Earlier Version", "B, Assets/logo.png, Working Copy"])
    // Hide Footer holds for every window, this one too.
    for command in SessionCommand.allCases {
      let acts = command == .skipRemainingFiles || command == .toggleFooter
      #expect(controller.canPerform(command) == acts, "\(command)")
    }
    #expect(countLabel(of: controller) == "")
    #expect(try toolbarItems(of: controller)[.changeNavigation]?.isHidden == true)

    controller.close()

    #expect(outcomes == [.saved])
  }

  @Test func commandsOfTheBaseAndTheResultDoNothingInAComparison() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())

    controller.toggleResultMaximized(nil)
    controller.toggleBase(nil)

    #expect(!controller.layout.maximizesResult)
    #expect(!controller.layout.showsBase)
    #expect(controller.layout.sourcePanes.allSatisfy { !$0.pane.isHidden })
  }

  @Test func swapSidesActsOnlyInAComparison() async throws {
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld())
    #expect(!merge.canPerform(.swapSides))
    #expect(Keys.of(.swapSides, in: .diff) == Keys("s", [.option, .command]))
  }

  /// The text of each highlight of `block` in `pane`; a mark where text is missing is empty.
  private func highlightedText(ofBlock block: Int, in pane: PaneView) throws -> [String] {
    let text = pane.content.text as NSString
    return try #require(pane.highlightProvider).highlights(forBlock: block).map { range in
      text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }
  }

  /// The pane on the left and the pane on the right.
  private func panes(of controller: SessionWindowController) throws -> (PaneView, PaneView) {
    let panes = controller.layout.sourcePanes.map(\.pane)
    try #require(panes.count == 2)
    return (panes[0], panes[1])
  }

  /// The items of the toolbar of the window, by their identifiers.
  private func toolbarItems(
    of controller: SessionWindowController
  ) throws -> [NSToolbarItem.Identifier: NSToolbarItem] {
    let toolbar = try #require(controller.window?.toolbar)
    return Dictionary(toolbar.items.map { ($0.itemIdentifier, $0) }) { first, _ in first }
  }

  private func countLabel(of controller: SessionWindowController) -> String? {
    controller.toolbar.toolbar.items.first { $0.itemIdentifier == .changeCount }?.view?
      .accessibilityLabel()
  }
}
