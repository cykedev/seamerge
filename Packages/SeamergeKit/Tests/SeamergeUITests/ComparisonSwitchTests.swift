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
    await controller.comparisonSwitcher.bringingBack?.value
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(controller.presentation.changes.blocks.count == blocksBefore)
    #expect(window.subtitle == subtitleBefore)
    undoManager.redo()
    await controller.comparisonSwitcher.bringingBack?.value
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
    presentation.show(.merge(ResultState(document: document, text: text)))
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

  /// The progress shows only once a comparison takes a moment, so this waits past that moment
  /// after a quick one.
  @Test func quickComparisonAnewNeverSaysThatItCompares() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    defer { controller.window?.close() }
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }

    await controller.comparisonSwitcher.whileComparingAnew {}
    try await Task.sleep(for: ComparisonSwitcher.progressDelay * 2)

    #expect(!controller.showsComparisonProgress)
    #expect(!announcements.contains(SessionToolbar.comparingText))
  }

  @Test func secondSwitchWhileOneIsUnderWayDoesNothing() async throws {
    let controller = try Windows.controller(for: try await decidedSample())
    let first = Task { await controller.switchComparison(to: ComparisonOptions(mode: .exact)) }
    await Task.yield()
    #expect(controller.comparisonSwitcher.isComparing)
    #expect(!controller.canPerform(.ignoreAllWhitespace))
    await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    await first.value
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(!controller.comparisonSwitcher.isComparing)
  }

  @Test func decisionMadeWhileTheSwitchIsUnderWayIsKept() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    defer { controller.window?.close() }
    #expect(controller.presentation.navigation.openConflictCount > 0)
    let switching = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    }
    await Task.yield()
    #expect(controller.comparisonSwitcher.isComparing)
    controller.resolveOpenConflicts(with: [.a])
    #expect(controller.presentation.navigation.openConflictCount == 0)

    await switching.value
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(controller.presentation.navigation.openConflictCount == 0)
    #expect(
      try controller.mergeResult.content.blocks.count
        == controller.presentation.changes.blocks.count)
  }

  @Test func arrangementChangedWhileTheSwitchIsUnderWayShowsTheNewComparisonInIt() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.everyKindOfChange())
    defer { controller.window?.close() }
    #expect(controller.presentation.alignsLines)
    let switching = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    }
    await Task.yield()
    #expect(controller.comparisonSwitcher.isComparing)
    controller.presentation.setAlignsLines(false)

    await switching.value
    let presentation = controller.presentation
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(!presentation.alignsLines)
    for (role, pane) in controller.layout.sourcePanes {
      #expect(
        pane.content.lineNumbers.count == presentation.changes.session.rowLayout.lineCount(in: role)
      )
      #expect(pane.content.blocks.count == presentation.changes.blocks.count)
    }
  }

  @Test func switchPreparesWhatThePanesShowAsShowingTheComparisonDirectly() async throws {
    let session = try await SampleDiffs.everyKindOfChange()
    let exact = try await session.recomputed(options: ComparisonOptions(mode: .exact))
    for alignsLines in [true, false] {
      let prepared = try Windows.controller(for: session)
      let direct = try Windows.controller(for: session)
      defer {
        prepared.window?.close()
        direct.window?.close()
      }
      for controller in [prepared, direct] {
        controller.presentation.setAlignsLines(alignsLines)
      }
      let contents = await prepared.prepared(.comparison(exact))
      prepared.presentation.showComparedAnew(contents)
      direct.presentation.show(.comparison(exact))
      for (shown, expected) in zip(Windows.panes(of: prepared), Windows.panes(of: direct)) {
        #expect(shown.documentView.string == expected.documentView.string)
        #expect(shown.content.lineNumbers == expected.content.lineNumbers)
        #expect(shown.content.blocks == expected.content.blocks)
        #expect(shown.collapsedRuns == expected.collapsedRuns)
      }
      #expect(
        prepared.presentation.sourcesOverviewBar.marks
          == direct.presentation.sourcesOverviewBar.marks)
      #expect(prepared.presentation.currentBlock == direct.presentation.currentBlock)
    }
  }

  @Test func decisionMadeWhileTheSwitchPreparesThePanesIsKept() async throws {
    let prompts = PromptRecorder()
    prompts.switchesAnyway = true
    let controller = try Windows.controller(for: try await twoConflicts(), prompts: prompts)
    defer { controller.window?.close() }
    let conflicts = conflictIndices(of: controller)
    try #require(conflicts.count == 2)
    controller.presentation.setCurrentBlock(conflicts[0])
    controller.perform(.useA)
    var intervenes = true
    prompts.whileAskingToDiscard = {
      guard intervenes else { return }
      intervenes = false
      // Runs as soon as the main actor is free, once the answer let the switch go on to make
      // the new panes ready away from it.
      Task { @MainActor in
        controller.presentation.setCurrentBlock(conflicts[1])
        controller.perform(.useB)
      }
    }

    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(prompts.discardedCounts == [1, 1])
    #expect(controller.presentation.navigation.openConflictCount == 1)
    let decided = try #require(conflictIndices(of: controller).last)
    let block = controller.presentation.changes.blocks[decided]
    #expect(controller.presentation.result?.document.segment(for: block).state == .chosen)
  }

  @Test func decisionMadeWhileTheSwitchAsksGoesIntoTheSwitch() async throws {
    let prompts = PromptRecorder()
    prompts.switchesAnyway = true
    let controller = try Windows.controller(for: try await twoConflicts(), prompts: prompts)
    defer { controller.window?.close() }
    let conflicts = conflictIndices(of: controller)
    controller.presentation.setCurrentBlock(conflicts[0])
    controller.perform(.useA)
    var intervenes = true
    prompts.whileAskingToDiscard = {
      guard intervenes else { return }
      intervenes = false
      controller.presentation.setCurrentBlock(conflicts[1])
      controller.perform(.useB)
    }

    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(prompts.discardedCounts == [1, 1])
    #expect(controller.presentation.navigation.openConflictCount == 1)
  }

  @Test func arrangementChangedWhileTheSwitchPreparesThePanesShowsItsNewComparison()
    async throws
  {
    let prompts = PromptRecorder()
    prompts.switchesAnyway = true
    let controller = try Windows.controller(for: try await twoConflicts(), prompts: prompts)
    defer { controller.window?.close() }
    controller.presentation.setCurrentBlock(conflictIndices(of: controller)[0])
    controller.perform(.useA)
    var intervenes = true
    prompts.whileAskingToDiscard = {
      guard intervenes else { return }
      intervenes = false
      Task { @MainActor in controller.presentation.setAlignsLines(false) }
    }

    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    let presentation = controller.presentation
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(!presentation.alignsLines)
    for (role, pane) in controller.layout.sourcePanes {
      #expect(
        pane.content.lineNumbers.count
          == max(presentation.changes.session.rowLayout.lineCount(in: role), 1))
    }
  }

  /// The indices of the conflicts among the changed blocks of the window.
  private func conflictIndices(of controller: SessionWindowController) -> [Int] {
    controller.presentation.changes.blocks.indices.filter {
      controller.presentation.changes.blocks[$0].kind == .conflict
    }
  }

  /// A merge with two conflicts: the first, like ``decidedSample()``, takes other lines in the
  /// exact mode, so that switching to it discards its decision; the second stays as it is.
  private func twoConflicts() async throws -> Session {
    try await SampleMerges.merge(
      base: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n",
      a: "one \nTWO\nthree\nfour\nfive\nsix\nSEVEN\neight\n",
      b: "one\nTwo\nthree\nfour\nfive\nsix\nSeven\neight\n")
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

  @Test func switchKeepsALastChangeThatRemovedTheEndOfTheNewerFile() async throws {
    // The change has no lines in B; it lies past the last line of B.
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: "one\ntwo\nthree\n", new: "one\n"))
    controller.selectLastChange(nil)
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(controller.presentation.currentBlock == 0)
    #expect(controller.presentation.changes.blocks.count == 1)
  }

  @Test func switchKeepsAChangeCurrentWhenSideBIsEmpty() async throws {
    let controller = try Windows.controller(
      for: try await SampleDiffs.diff(old: "one\ntwo\n", new: ""))
    controller.selectLastChange(nil)
    #expect(controller.presentation.currentBlock == 0)
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    #expect(controller.presentation.changes.blocks.count == 1)
    #expect(controller.presentation.currentBlock == 0)
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
