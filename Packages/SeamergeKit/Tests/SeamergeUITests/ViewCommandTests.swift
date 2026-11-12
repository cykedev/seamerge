import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The commands of the View menu, Go to Line and Open in Editor: what each changes, its name
/// while it is on, and when it is valid.
@MainActor
@Suite struct ViewCommandTests {
  @Test func hidingTheBaseGivesItsWidthToAAndBAndMovesTheConflictMarkToB() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let layout = controller.layout
    let base = try #require(layout.sourcePane(.base))
    let a = try #require(layout.sourcePane(.a))
    let b = try #require(layout.sourcePane(.b))
    let conflict = try #require(controller.presentation.navigation.firstOpenConflict)
    #expect(base.content.blocks[conflict].conflict == .open)
    #expect(b.content.blocks[conflict].conflict == nil)
    #expect(title(of: .toggleBase, in: controller) == "Hide Base")

    controller.toggleBase(nil)
    layout.view.layoutSubtreeIfNeeded()
    #expect(!base.isShown)
    #expect(abs(a.frame.width - b.frame.width) <= 1)
    #expect(b.content.blocks[conflict].conflict == .open)
    #expect(title(of: .toggleBase, in: controller) == "Show Base")
    #expect(controller.focusablePanes.count == 3)

    controller.toggleBase(nil)
    layout.view.layoutSubtreeIfNeeded()
    #expect(base.isShown)
    #expect(abs(a.frame.width - base.frame.width) <= 1)
    #expect(base.content.blocks[conflict].conflict == .open)
  }

  @Test func hidingTheBaseWhileItHasTheFocusHandsTheFocusToB() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    let base = try #require(controller.layout.sourcePane(.base))
    window.makeFirstResponder(base.documentView)
    controller.toggleBase(nil)
    #expect(window.firstResponder === controller.layout.sourcePane(.b)?.documentView)
    #expect(controller.isInBlockMode)
    #expect(!controller.focusablePanes.contains { $0 === base })
  }

  @Test func dividersCannotCollapseAPane() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let layout = controller.layout
    let sources = try #require(
      layout.splitViewItems.first?.viewController as? NSSplitViewController)
    sources.splitView.setPosition(0, ofDividerAt: 0)
    sources.splitView.setPosition(sources.splitView.bounds.width, ofDividerAt: 1)
    layout.splitView.setPosition(0, ofDividerAt: 0)
    layout.view.layoutSubtreeIfNeeded()
    #expect(sources.splitViewItems.allSatisfy { !$0.isCollapsed })
    #expect(layout.splitViewItems.allSatisfy { !$0.isCollapsed })
    for pane in Windows.panes(of: controller) {
      #expect(pane.isShown)
      #expect(pane.frame.width >= pane.minimumWidth - 1)
    }
  }

  @Test func mergeWithoutABaseCannotHideIt() async throws {
    let session = try await SampleMerges.merge(
      base: nil, a: "same\nfrom a\nsame again\n", b: "same\nfrom b\nsame again\n")
    let controller = try Windows.controller(for: session)
    #expect(!controller.canPerform(.toggleBase))
  }

  @Test func maximizingTheResultCollapsesThePanesAboveAndMovesTheFocusIntoIt() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    #expect(controller.isInBlockMode)
    controller.toggleResultMaximized(nil)
    controller.layout.view.layoutSubtreeIfNeeded()
    #expect(controller.layout.sourcePanes.allSatisfy { !$0.pane.isShown })
    #expect(controller.isInTextMode)
    #expect(title(of: .toggleResultMaximized, in: controller) == "Restore Layout")
    #expect(!controller.canPerform(.toggleBase))
    controller.toggleResultMaximized(nil)
    controller.layout.view.layoutSubtreeIfNeeded()
    #expect(controller.layout.sourcePanes.allSatisfy { $0.pane.isShown })
    #expect(title(of: .toggleResultMaximized, in: controller) == "Maximize Result")
  }

  @Test func turningOffSynchronizedScrollingLetsEachPaneScrollOnItsOwn() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let a = try #require(controller.layout.sourcePane(.a))
    let result = controller.layout.resultPane
    let item = menuItem(for: .toggleScrollSynchronization, in: controller)
    #expect(item.state == .on)
    controller.toggleScrollSynchronization(nil)
    #expect(menuItem(for: .toggleScrollSynchronization, in: controller).state == .off)
    let resultOffset = Windows.scrollOffset(of: result)
    a.documentView.scroll(CGPoint(x: 0, y: 600))
    #expect(Windows.scrollOffset(of: result) == resultOffset)
  }

  @Test func invisiblesShowInEveryPane() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    controller.toggleInvisibles(nil)
    #expect(Windows.panes(of: controller).allSatisfy { $0.showsInvisibles })
    #expect(title(of: .toggleInvisibles, in: controller) == "Hide Invisibles")
    controller.toggleInvisibles(nil)
    #expect(Windows.panes(of: controller).allSatisfy { !$0.showsInvisibles })
  }

  @Test func showAllLinesIsValidOnlyWhereThereAreRunsToShowOrCollapse() async throws {
    let short = try Windows.controller(for: try await SampleMerges.manyBlocks())
    #expect(Windows.panes(of: short).allSatisfy { $0.collapsedRuns.isEmpty })
    #expect(!short.canPerform(.toggleCollapsedLines))

    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let long = try Windows.controller(for: session)
    #expect(long.canPerform(.toggleCollapsedLines))
    for run in long.layout.sourcePanes[0].pane.collapsedRuns {
      long.presentation.pane(long.layout.sourcePanes[0].pane, didAskToExpand: run)
    }
    #expect(!long.canPerform(.toggleCollapsedLines))
    long.toggleCollapsedLines(nil)
    #expect(long.canPerform(.toggleCollapsedLines))
  }

  @Test func showAllLinesExpandsEveryRunAndCollapseBringsThemBack() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let panes = Windows.panes(of: controller)
    #expect(panes.allSatisfy { !$0.collapsedRuns.isEmpty })
    #expect(title(of: .toggleCollapsedLines, in: controller) == "Show All Lines")
    controller.toggleCollapsedLines(nil)
    #expect(panes.allSatisfy { $0.collapsedRuns.isEmpty })
    #expect(title(of: .toggleCollapsedLines, in: controller) == "Collapse Unchanged Lines")
    controller.toggleCollapsedLines(nil)
    #expect(panes.allSatisfy { !$0.collapsedRuns.isEmpty })
  }

  @Test func zoomStepsThroughTheSizesAndKeepsTheLineAtTheReadingLine() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let b = try #require(controller.layout.sourcePane(.b))
    controller.presentation.jump(to: 20)
    let line = lineAtReadingLine(of: b)
    #expect(!controller.canPerform(.actualSize))
    controller.zoomIn(nil)
    #expect(controller.fontSize == 14)
    #expect(b.theme.font.pointSize == 14)
    #expect(controller.layout.resultPane.theme.font.pointSize == 14)
    #expect(abs(lineAtReadingLine(of: b) - line) <= 1)
    controller.actualSize(nil)
    #expect(controller.fontSize == SessionWindowController.standardFontSize)
    while controller.canPerform(.zoomOut) {
      controller.zoomOut(nil)
    }
    #expect(controller.fontSize == 10)
    #expect(abs(lineAtReadingLine(of: b) - line) <= 1)
  }

  @Test func goToLineExpandsItsRunAndPutsItAtTheReadingLine() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let a = try #require(controller.layout.sourcePane(.a))
    let hidden = try #require(a.collapsedRuns.dropFirst(5).first)
    let line = Int(a.content.lineNumbers[hidden.rows.lowerBound + 2]) + 1
    controller.go(toLine: line, in: a)
    #expect(!a.collapsedRuns.contains(hidden))
    #expect(lineAtReadingLine(of: a) == line - 1)

    let block = 9
    let changedLine = Int(a.content.lineNumbers[a.content.blocks[block].rows.lowerBound]) + 1
    controller.go(toLine: changedLine, in: a)
    #expect(controller.presentation.currentBlock == block)
  }

  @Test func goToLineInTheResultPutsTheInsertionPointThereInTextMode() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let result = controller.layout.resultPane
    controller.enterTextMode()
    #expect(controller.focusedPane === result)
    controller.go(toLine: 120, in: result)
    #expect(result.documentView.selectedRange().location == result.content.offset(ofRow: 119))
    #expect(lineAtReadingLine(of: result) == 119)
  }

  @Test func openInEditorOpensTheResultFileAndNeedsOneOnDisk() async throws {
    let session = try await SampleMerges.helloWorld()
    let missing = try Windows.controller(for: session, context: SampleMerges.helloWorldContext)
    #expect(!missing.canPerform(.openInEditor))
    #expect(try !Windows.controller(for: session).canPerform(.openInEditor))

    let url = FileManager.default.temporaryDirectory.appending(
      path: "SeamergeUITests-\(UUID().uuidString).java")
    try Data(SampleMerges.helloWorldB.utf8).write(to: url)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: url) } }
    let workspace = WorkspaceRecorder()
    let controller = try Windows.controller(
      for: session, context: SessionContext(resultURL: url), workspace: workspace)
    #expect(controller.canPerform(.openInEditor))
    controller.openInEditor(nil)
    #expect(workspace.openedURLs == [url])
  }

  @Test func commandsOfTheViewMenuFollowTheKeysOfTheConcept() {
    let option: NSEvent.ModifierFlags = [.option, .command]
    #expect(Keys.of(.toggleBase, in: .merge) == Keys("b", option))
    #expect(Keys.of(.toggleResultMaximized, in: .merge) == Keys("r", option))
    #expect(Keys.of(.toggleInvisibles, in: .merge) == nil)
    #expect(Keys.of(.toggleCollapsedLines, in: .merge) == Keys("l", [.shift, .command]))
    #expect(Keys.of(.toggleScrollSynchronization, in: .merge) == Keys("y", [.option, .command]))
    #expect(Keys.of(.zoomIn, in: .merge) == Keys("+", .command))
    #expect(Keys.of(.zoomOut, in: .merge) == Keys("-", .command))
    #expect(Keys.of(.actualSize, in: .merge) == Keys("0", .command))
    #expect(Keys.of(.goToLine, in: .merge) == Keys("l", .command))
    #expect(Keys.of(.openInEditor, in: .merge) == Keys("o", [.option, .command]))
  }

  /// The menu item of `command` after the window validated it.
  private func menuItem(
    for command: SessionCommand, in controller: SessionWindowController
  ) -> NSMenuItem {
    let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
    _ = controller.validateUserInterfaceItem(item)
    return item
  }

  private func title(of command: SessionCommand, in controller: SessionWindowController) -> String {
    menuItem(for: command, in: controller).title
  }

  /// The line of the file of `pane`, counted from 0, at its reading line.
  private func lineAtReadingLine(of pane: PaneView) -> Int {
    let visible = pane.documentView.visibleRect
    let point = pane.convert(
      CGPoint(x: 0, y: visible.minY + Theme.readingLine * visible.height + 1),
      from: pane.documentView)
    return Int(pane.content.lineNumbers[pane.hit(at: point).row])
  }
}
