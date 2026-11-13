import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The window around the panes: their order, sizes, names and headers, the title, and how the
/// window ends.
@MainActor
@Suite struct SessionWindowTests {
  @Test func panesStandInTheOrderABaseBAndEachHasAVoiceOverName() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    let controller = makeController(session, context: context)
    #expect(controller.layout.sourcePanes.map(\.role) == [.a, .base, .b])
    let names = controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() }
    #expect(names[0] == "A, feature, incoming")
    #expect(names[1]?.hasPrefix("Base, ") == true)
    #expect(names[2] == "B, main, yours")
    #expect(try controller.mergeResult.accessibilityLabel()?.hasPrefix("Result, ") == true)
    #expect(try controller.mergeResult.accessibilityLabel()?.hasSuffix("story.txt") == true)
  }

  @Test func paneWithoutGitIsNamedAfterItsFile() async throws {
    let session = try await SampleMerges.helloWorld()
    let controller = makeController(session, context: SessionContext())
    let names = controller.layout.sourcePanes.map { $0.pane.accessibilityLabel() }
    #expect(names == ["A, HelloWorld1.java", "Base, HelloWorld0.java", "B, HelloWorld2.java"])
    #expect(try controller.mergeResult.accessibilityLabel() == "Result")
  }

  @Test func mergeWithoutABaseHasNoBasePane() async throws {
    let session = try await SampleMerges.merge(
      base: nil, a: "same\nfrom a\nsame again\n", b: "same\nfrom b\nsame again\n")
    #expect(makeController(session).layout.sourcePanes.map(\.role) == [.a, .b])
  }

  @Test func ordinaryMergePutsTheRoleAfterTheName() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    let header = SideHeader(role: .a, session: session, context: context)
    #expect(header.name == "feature")
    #expect(header.roleText == "incoming")
    #expect(header.rolePlacement == .afterName)
  }

  @Test(arguments: ["rebase", "cherry-pick", "revert"])
  func otherOperationsPutTheRoleBeforeTheName(scenario name: String) async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == name })
    let (session, context) = try await scenario.load()
    let header = SideHeader(role: .a, session: session, context: context)
    #expect(header.roleText != nil)
    #expect(header.rolePlacement == .beforeName)
    #expect(header.spokenName.hasPrefix("A, \(header.roleText ?? ""), "))
  }

  @Test func nameOfAFileWithALineBreakStandsOnOneLine() async throws {
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("one\ntwo\n".utf8), label: "base"),
      a: SourceFile(bytes: Data("one\n".utf8), label: "first\nline\u{2028}name"),
      b: SourceFile(bytes: Data("one\nTWO\n".utf8), label: "b"))

    let header = SideHeader(role: .a, session: session, context: SessionContext())
    #expect(header.name == "first line name")
    // The preview of the conflict names the side that removed the line, and the window opens.
    let controller = try Windows.controller(for: session)
    #expect(try controller.mergeResult.content.text.contains("first line name removed these lines"))
  }

  @Test func disconnectedCallerAddsALineBelowTheResultHeader() async throws {
    let session = try await SampleMerges.helloWorld()
    let controller = makeController(session)
    let header = try #require(
      controller.layout.splitViewItems.last?.topAlignedAccessoryViewControllers.first?.view)
    #expect(header.fittingSize.height == WindowMetrics.headerHeight)
    controller.callerDisconnected()
    header.layoutSubtreeIfNeeded()
    #expect(header.fittingSize.height == WindowMetrics.headerHeight + WindowMetrics.noticeHeight)
  }

  @Test func windowRepresentsTheResultFile() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    let window = try #require(makeController(session, context: context).window)
    #expect(window.representedURL == context.resultURL)
  }

  @Test func titleNamesTheResultFileAndTheSubtitleCountsTheChanges() async throws {
    let (session, context) = try await Scenario.merges[0].load()
    let controller = makeController(session, context: context)
    let window = try #require(controller.window)
    #expect(window.title == "story.txt")
    #expect(window.subtitle == "1 change from A · 1 from B")
    #expect(window.representedURL == context.resultURL)
    #expect(window.accessibilityTitle() == "story.txt, 1 change from A · 1 from B")
  }

  @Test func subtitleSaysNothingOfTheComparisonInTheDefaultMode() async throws {
    let session = try await SampleMerges.helloWorld()
    let inDefaultMode = try await session.recomputed(
      options: ComparisonOptions(mode: .windowDefault))
    let summary = SessionSummary(
      changes: SessionChanges(session: inDefaultMode), context: .init(),
      arrangement: PaneArrangement(session: inDefaultMode))
    #expect(summary.changes == "3 changes from A · 1 from B")
    #expect(ComparisonMode.windowDefault == .ignoreWhitespaceAmount)
  }

  @Test(arguments: ComparisonMode.allCases.filter { $0 != .windowDefault })
  func subtitleNamesAComparisonModeOtherThanTheDefault(mode: ComparisonMode) async throws {
    let session = try await SampleMerges.helloWorld()
    let other = try await session.recomputed(options: ComparisonOptions(mode: mode))
    let summary = SessionSummary(
      changes: SessionChanges(session: other), context: .init(),
      arrangement: PaneArrangement(session: other))
    let note =
      switch mode {
      case .exact: "Compared exactly"
      case .ignoreLineEndings: "Line endings ignored"
      case .ignoreWhitespaceAmount: "Whitespace changes ignored"
      case .ignoreAllWhitespace: "All whitespace ignored"
      }
    #expect(summary.changes.hasSuffix(" · \(note)"))
  }

  @Test func narrowWindowDropsTheRebaseFromTheSubtitleFirst() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "rebase" })
    let (session, context) = try await scenario.load()
    let summary = SessionSummary(
      changes: SessionChanges(session: session), context: context,
      arrangement: PaneArrangement(session: session))
    let font = NSFont.preferredFont(forTextStyle: .subheadline)
    #expect(summary.fullSubtitle == "1 change from A · 1 from B · Rebase onto main · Commit 2 of 3")
    #expect(summary.subtitle(fittingWidth: 1000, font: font) == summary.fullSubtitle)
    #expect(summary.subtitle(fittingWidth: 200, font: font) == "1 change from A · 1 from B")

    let window = try #require(makeController(session, context: context).window)
    #expect(window.subtitle == summary.fullSubtitle)
    #expect(window.accessibilityTitle() == "notes.txt, \(summary.fullSubtitle)")
  }

  @Test func remainingFilesWithConflictsFollowTheChanges() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "many" })
    let (session, context) = try await scenario.load()
    let summary = SessionSummary(
      changes: SessionChanges(session: session), context: context,
      arrangement: PaneArrangement(session: session))
    #expect(summary.fullSubtitle == "1 change from A · 1 from B · 11 more files with conflicts")
  }

  @Test func closingReportsCancelledExactlyOnce() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }
    let window = try #require(controller.window)
    window.close()
    window.close()
    #expect(outcomes.count == 1)
    #expect(outcomes.first.map { if case .cancelled = $0 { true } else { false } } == true)
  }

  @Test func windowUsesTheUndoManagerOfTheSessionAndHasNoTabs() async throws {
    let session = try await SampleMerges.helloWorld()
    let undoManager = UndoManager()
    let controller = SessionWindowController(session: session, undoManager: undoManager)
    let window = try #require(controller.window)
    #expect(window.undoManager === undoManager)
    #expect(window.tabbingMode == .disallowed)
  }

  @Test func newWindowGivesTheSourcesEqualWidthsAndMoreThanHalfTheHeight() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    let widths = controller.layout.sourcePanes.map(\.pane.frame.width)
    #expect(widths.max().map { $0 - (widths.min() ?? 0) <= 1 } == true)
    let sources = try #require(controller.layout.splitViewItems.first?.viewController.view)
    let fraction = sources.frame.height / controller.layout.splitView.bounds.height
    #expect(abs(fraction - WindowMetrics.sourcesFraction) < 0.01)
  }

  @Test func smallestWindowKeepsEveryPaneAtItsLeastWidth() async throws {
    let controller = makeController(try await SampleMerges.helloWorld())
    let window = try #require(controller.window)
    window.setContentSize(window.contentMinSize)
    window.contentView?.layoutSubtreeIfNeeded()
    for (_, pane) in controller.layout.sourcePanes {
      #expect(pane.frame.width >= pane.minimumWidth)
    }
    #expect(controller.layout.view.frame.height <= window.contentMinSize.height)
  }

  @Test func changingTheDisplayOptionsRedrawsWithTheirTheme() async throws {
    let session = try await SampleMerges.helloWorld()
    let controller = makeController(session, context: SessionContext())
    controller.displayOptions = DisplayOptions(differentiatesWithoutColor: true)
    for pane in controller.presentation.allPanes {
      #expect(pane.theme.differentiatesWithoutColor)
    }
    #expect(controller.presentation.sourcesOverviewBar.theme.differentiatesWithoutColor)
    #expect(try controller.presentation.mergeDecisionColumn.theme.differentiatesWithoutColor)
  }

  private func makeController(
    _ session: Session, context: SessionContext = SessionContext()
  ) -> SessionWindowController {
    SessionWindowController(
      session: session, context: context, undoManager: UndoManager(),
      displayOptions: DisplayOptions(), pasteboard: .withUniqueName(),
      workspace: WorkspaceRecorder(),
      prompts: PromptRecorder(), doneStyle: .standard, defaults: .privateSuite(),
      window: SessionWindow())
  }
}
