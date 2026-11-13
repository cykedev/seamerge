import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Switching to another comparison mode or merge strategy: the window compares anew, keeps the
/// line of B where it is, names the mode in the subtitle, and undoes the switch in one step.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ComparisonSwitchTests {
  @Test func switchShowsTheNewComparisonAndUndoesInOneStep() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "whitespace" })
    let (session, context) = try await scenario.load()
    // Without events to group them, the steps of undo are grouped by hand.
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: session, context: context, undoManager: undoManager)
    let window = try #require(controller.window)
    #expect(window.undoManager === undoManager)
    let blocksBefore = controller.presentation.changes.blocks.count
    let subtitleBefore = window.subtitle

    undoManager.beginUndoGrouping()
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    undoManager.endUndoGrouping()
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(controller.presentation.changes.blocks.count > blocksBefore)
    #expect(window.subtitle.hasSuffix("Compared exactly"))
    #expect(
      try controller.mergeResult.content.blocks.count
        == controller.presentation.changes.blocks.count)
    #expect(undoManager.undoMenuItemTitle == "Undo Change Comparison")

    undoManager.undo()
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(controller.presentation.changes.blocks.count == blocksBefore)
    #expect(window.subtitle == subtitleBefore)
    undoManager.redo()
    #expect(controller.comparisonOptions.mode == .exact)
  }

  @Test func switchRebuildsTheWindowOfABigFileQuicklyAndKeepsTheLineOfB() async throws {
    let scenario = try #require(Scenario.merges.first { $0.name == "big" })
    let (session, context) = try await scenario.load()
    let controller = try Windows.controller(for: session, context: context)
    let presentation = controller.presentation
    let b = try #require(controller.layout.sourcePane(.b))
    presentation.jump(to: presentation.changes.blocks.count / 2)
    let lineBefore = try #require(lineOfB(atReadingLineOf: b, in: controller))
    // The engine compares off the main thread while the window shows the old comparison; what
    // the user waits for at the end is the window showing the new one.
    let switched = try await session.recomputed(options: ComparisonOptions(mode: .exact))
    let result = try presentation.mergeResult
    var document = result.document
    let modeSwitch = document.planSwitching(to: switched, text: result.text)
    _ = document.apply(modeSwitch.plan, replacedTexts: [result.text])
    let text = modeSwitch.plan.replacements.map(\.text).joined()

    let start = ContinuousClock.now
    presentation.show(document.session, result: ResultState(document: document, text: text))
    let duration = ContinuousClock.now - start
    #expect(duration < .seconds(1), "rebuilding took \(duration)")
    #expect(presentation.changes.session.options.mode == .exact)
    let lineAfter = try #require(lineOfB(atReadingLineOf: b, in: controller))
    #expect(abs(lineAfter - lineBefore) <= 1)
  }

  @Test func switchThatWouldDiscardDecisionsAsksFirstAndKeepsThemWhenCancelled() async throws {
    let prompts = PromptRecorder()
    let controller = try Windows.controller(for: try await decidedSample(), prompts: prompts)
    controller.resolveOpenConflicts(with: [.a])
    let result = try controller.presentation.mergeResult
    let exact = try await result.document.session.recomputed(
      options: ComparisonOptions(mode: .exact))
    let expected = result.document.planSwitching(to: exact, text: result.text)
      .discardedDecisionCount
    #expect(expected > 0)

    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(prompts.discardedCounts == [expected])
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(controller.presentation.navigation.openConflictCount == 0)

    prompts.switchesAnyway = true
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(prompts.discardedCounts == [expected, expected])
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(controller.presentation.navigation.openConflictCount > 0)
  }

  @Test func failedComparisonIsReportedAndKeepsTheComparisonShown() async throws {
    let prompts = PromptRecorder()
    let controller = try Windows.controller(for: try await decidedSample(), prompts: prompts)
    let blocks = controller.presentation.changes.blocks
    await controller.comparisonFailed(.comparisonFailed)
    #expect(prompts.failureCount == 1)
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(controller.presentation.changes.blocks == blocks)
  }

  @Test func secondSwitchWhileOneIsUnderWayDoesNothing() async throws {
    let controller = try Windows.controller(for: try await decidedSample())
    let first = Task { await controller.switchComparison(to: ComparisonOptions(mode: .exact)) }
    await Task.yield()
    #expect(controller.isSwitchingComparison)
    #expect(!controller.canPerform(.ignoreAllWhitespace))
    await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    await first.value
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(!controller.isSwitchingComparison)
  }

  /// A merge with one conflict in the mode of the window whose lines differ in the exact mode,
  /// where A also adds a trailing space to the line before it.
  private func decidedSample() async throws -> Session {
    try await SampleMerges.merge(
      base: "one\ntwo\nthree\nfour\n", a: "one \nTWO\nthree\nfour\n",
      b: "one\nTwo\nthree\nfour\n")
  }

  @Test func switchToAnotherStrategyKeepsTheMode() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    await controller.switchComparison(
      to: ComparisonOptions(mode: .windowDefault, strategy: .guarded))
    #expect(controller.comparisonOptions.strategy == .guarded)
    #expect(controller.comparisonOptions.mode == .windowDefault)
  }

  @Test func menuItemOfTheModeInUseHasACheckmark() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    for command in [
      SessionCommand.compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges,
      .ignoreAllWhitespace,
    ] {
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      #expect(controller.validateUserInterfaceItem(item))
      #expect((item.state == .on) == (command.comparisonMode == .windowDefault))
    }
    #expect(SessionCommand.ignoreWhitespaceChanges.help?.contains("“a  b”") == true)
    #expect(SessionCommand.ignoreAllWhitespace.help?.contains("“ab”") == true)
  }

  /// The line of B at the reading line of `pane`, counted from 0.
  private func lineOfB(
    atReadingLineOf pane: PaneView, in controller: SessionWindowController
  ) -> Int? {
    let visible = pane.documentView.visibleRect
    let point = pane.convert(
      CGPoint(x: 0, y: visible.minY + Theme.readingLine * visible.height + 1),
      from: pane.documentView)
    let row = pane.hit(at: point).row
    let line = pane.content.lineNumbers[row]
    return line >= 0 ? Int(line) : nil
  }
}
