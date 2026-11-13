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
    let result = try controller.mergeResult
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

  @Test func shortFilesHaveNothingToShowOrCollapse() async throws {
    let short = try Windows.controller(for: try await SampleMerges.manyBlocks())
    #expect(Windows.panes(of: short).allSatisfy { $0.collapsedRuns.isEmpty })
    #expect(!short.canPerform(.showAllLines))
    #expect(!short.canPerform(.collapseUnchangedLines))
  }

  @Test func eachOfTheThreeStatesOfCollapsingHasTheCommandsThatChangeIt() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let pane = controller.layout.sourcePanes[0].pane
    let runs = pane.collapsedRuns
    try #require(runs.count > 1)
    // As loaded, every run is collapsed.
    #expect(controller.canPerform(.showAllLines))
    #expect(!controller.canPerform(.collapseUnchangedLines))

    // One run expanded, the others collapsed: both change what the panes show.
    controller.presentation.pane(pane, didAskToExpand: runs[0])
    #expect(pane.expandedRuns == [runs[0]])
    #expect(controller.canPerform(.showAllLines))
    #expect(controller.canPerform(.collapseUnchangedLines))
    controller.collapseUnchangedLines(nil)
    #expect(pane.collapsedRuns == runs)
    #expect(pane.expandedRuns.isEmpty)

    // Every line shown.
    controller.showAllLines(nil)
    #expect(Windows.panes(of: controller).allSatisfy { $0.collapsedRuns.isEmpty })
    #expect(!controller.canPerform(.showAllLines))
    #expect(controller.canPerform(.collapseUnchangedLines))
    controller.collapseUnchangedLines(nil)
    #expect(pane.collapsedRuns == runs)
    #expect(title(of: .showAllLines, in: controller) == "Show All Lines")
    #expect(title(of: .collapseUnchangedLines, in: controller) == "Collapse Unchanged Lines")
  }

  @Test func signInTheGutterCollapsesOneExpandedRunInEveryPane() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let panes = Windows.panes(of: controller)
    let pane = controller.layout.sourcePanes[0].pane
    let runs = pane.collapsedRuns
    controller.presentation.pane(pane, didAskToExpand: runs[0])
    controller.presentation.pane(pane, didAskToExpand: runs[1])
    let collapsedPerPane = panes.map(\.collapsedRuns.count)

    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }
    pane.scroll(toPlaceRowAtReadingLine: runs[1].rows.lowerBound, motion: .cut)

    controller.presentation.pane(pane, didAskToCollapse: runs[1])

    #expect(pane.expandedRuns == [runs[0]])
    #expect(zip(panes, collapsedPerPane).allSatisfy { $0.collapsedRuns.count == $1 + 1 })
    #expect(announcements == ["Collapsed \(runs[1].rows.count) unchanged lines"])
    let focus = try #require(controller.window?.firstResponder as? NSButton)
    #expect(focus.accessibilityLabel()?.contains("unchanged lines") == true)
  }

  @Test func signToCollapseLeavesOutTheRunOfTheInsertionPointInTheResult() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    let controller = try Windows.controller(for: session)
    let source = controller.layout.sourcePanes[0].pane
    controller.presentation.pane(source, didAskToExpand: source.collapsedRuns[0])
    let result = try controller.mergeResult
    let run = try #require(result.expandedRuns.first)

    let textView = try controller.resultTextView
    textView.setSelectedRange(
      NSRange(location: result.content.offset(ofRow: run.rows.lowerBound + 1), length: 0))

    #expect(result.expandedRuns.isEmpty)
    controller.leaveTextMode()
    #expect(result.expandedRuns == [run])
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
    #expect(try controller.mergeResult.theme.font.pointSize == 14)
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
    let result = try controller.mergeResult
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
    #expect(Keys.of(.showAllLines, in: .merge) == Keys("l", [.shift, .command]))
    #expect(Keys.of(.collapseUnchangedLines, in: .merge) == Keys("l", [.option, .shift, .command]))
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
