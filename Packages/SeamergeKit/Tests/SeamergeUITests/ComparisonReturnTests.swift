import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Undo and redo of a switch of the comparison mode: the window makes the comparison they bring
/// back ready away from the main actor and takes no edit, no command and no other undo or redo
/// until it shows; afterwards everything works again, and each step brings back the text it
/// belongs to.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ComparisonReturnTests {
  /// The commands that a window can carry out while it cannot show the lines of its files.
  static let commandsWhileWaiting: [SessionCommand] = [
    .skipRemainingFiles, .toggleFooter, .nextFile, .previousFile, .filterFiles,
    .toggleIdenticalFiles, .copyPatch, .exportPatch,
  ]

  /// A window of a merge with a decided conflict, switched to comparing exactly, with the undo
  /// manager whose steps the test groups by hand, and the texts of the result's segments before
  /// and after the switch.
  private func switchedMerge() async throws -> (
    controller: SessionWindowController, undoManager: UndoManager, decided: [String],
    switched: [String]
  ) {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try Windows.controller(
      for: try await SampleMerges.manyBlocks(), undoManager: undoManager)
    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    undoManager.beginUndoGrouping()
    controller.perform(.useA)
    undoManager.endUndoGrouping()
    let decided = try controller.segmentTexts
    undoManager.beginUndoGrouping()
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    undoManager.endUndoGrouping()
    #expect(controller.comparisonOptions.mode == .exact)
    return (controller, undoManager, decided, try controller.segmentTexts)
  }

  /// Whether the window validates the menu item of `action`, as the Edit menu asks it.
  private func validates(_ action: String, in controller: SessionWindowController) throws -> Bool {
    let window = try #require(controller.window)
    return window.validateUserInterfaceItem(
      NSMenuItem(title: action, action: Selector((action)), keyEquivalent: ""))
  }

  @Test func windowTakesNoEditCommandOrUndoUntilUndoOfASwitchShowsItsComparison() async throws {
    let (controller, undoManager, decided, switched) = try await switchedMerge()
    defer { controller.window?.close() }
    let textView = try controller.resultTextView
    let commandsBefore = SessionCommand.allCases.filter(controller.canPerform)
    #expect(try validates("undo:", in: controller))

    undoManager.undo()
    #expect(controller.comparisonReturn != nil)
    #expect(!textView.isEditable)
    #expect(
      SessionCommand.allCases.filter(controller.canPerform).allSatisfy(
        Self.commandsWhileWaiting.contains))
    #expect(try !validates("undo:", in: controller))
    #expect(try !validates("redo:", in: controller))
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(try controller.segmentTexts == switched, "typing changes nothing while it waits")

    await controller.comparisonReturn?.value
    #expect(controller.comparisonReturn == nil)
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(try controller.segmentTexts == decided)
    try controller.checkResultIsShownAsModelled()
    #expect(textView.isEditable)
    #expect(SessionCommand.allCases.filter(controller.canPerform).count >= commandsBefore.count)
    #expect(try validates("undo:", in: controller))
    #expect(try validates("redo:", in: controller))
  }

  @Test func undoAndRedoOfASwitchEachBringBackTheTextTheirStepBelongsTo() async throws {
    let (controller, undoManager, decided, switched) = try await switchedMerge()
    defer { controller.window?.close() }

    undoManager.undo()
    await controller.comparisonReturn?.value
    #expect(try controller.segmentTexts == decided)
    #expect(undoManager.redoActionName == SessionWindowController.switchName)

    undoManager.redo()
    #expect(controller.comparisonReturn != nil)
    await controller.comparisonReturn?.value
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(try controller.segmentTexts == switched)
    try controller.checkResultIsShownAsModelled()

    undoManager.undo()
    await controller.comparisonReturn?.value
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(try controller.segmentTexts == decided)
    // The step before the switch, the decision, belongs to the text the undo brought back.
    undoManager.undo()
    #expect(controller.comparisonReturn == nil)
    #expect(controller.presentation.navigation.openConflictCount > 0)
    try controller.checkResultIsShownAsModelled()
    #expect(!undoManager.canUndo)
  }

  @Test func switchCannotBeUndoneWhileAnotherComparisonIsUnderWay() async throws {
    let (controller, undoManager, _, _) = try await switchedMerge()
    defer { controller.window?.close() }
    let switching = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    }
    await Task.yield()
    #expect(controller.isSwitchingComparison)
    #expect(try !validates("undo:", in: controller))
    // The switch registers its step once it shows, after it compared away from the main actor.
    undoManager.beginUndoGrouping()
    await switching.value
    undoManager.endUndoGrouping()
    #expect(try validates("undo:", in: controller))
  }

  @Test func undoRightAfterASwitchWasSetOffBringsBackItsComparisonAndTheSwitchDoesNothing()
    async throws
  {
    let (controller, undoManager, decided, _) = try await switchedMerge()
    defer { controller.window?.close() }
    // Both come in one after the other before either runs, as a key of a mode and Command-Z.
    let queued = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    }
    undoManager.undo()
    await queued.value
    await controller.comparisonReturn?.value
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(try controller.segmentTexts == decided)
    try controller.checkResultIsShownAsModelled()
    #expect(undoManager.redoActionName == SessionWindowController.switchName)
  }

  @Test func reloadSetOffBeforeUndoOfASwitchWaitsUntilTheComparisonIsBack() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "ComparisonReturnTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let old = folder.appending(path: "old.txt")
    let new = folder.appending(path: "new.txt")
    try Data("a\nb  c\nd\n".utf8).write(to: old)
    try Data("a\nb c\nd\ne\n".utf8).write(to: new)
    let session = try await Session.loadDiff(
      old: SessionFile(url: old, label: "old.txt"), new: SessionFile(url: new, label: "new.txt"),
      mode: .windowDefault)
    // The reload registers its step on its own, in a group of the run loop.
    let undoManager = UndoManager()
    let controller = try Windows.controller(for: session, undoManager: undoManager)
    defer { controller.window?.close() }
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    try Data("a\nb c\nd\ne\nf\n".utf8).write(to: new)

    let reloading = Task { await controller.diskWatch.reloadChangedFiles() }
    undoManager.undo()
    await reloading.value
    // The reload waits for the comparison that undo brings back, then looks again.
    #expect(controller.presentation.changes.session.inputs.b.text == "a\nb c\nd\ne\n")
    await controller.comparisonReturn?.value
    #expect(controller.comparisonOptions.mode == .windowDefault)
    // The window looks again on its own once the comparison is back.
    while controller.presentation.changes.session.inputs.b.text != "a\nb c\nd\ne\nf\n",
      !Task.isCancelled
    {
      await Task.yield()
    }
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(undoManager.undoActionName == SessionWindowController.reloadName)
  }

  @Test func decisionCanBeUndoneWhileASwitchIsUnderWay() async throws {
    let (controller, undoManager, _, _) = try await switchedMerge()
    defer { controller.window?.close() }
    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    undoManager.beginUndoGrouping()
    controller.perform(.useB)
    undoManager.endUndoGrouping()
    let decided = try controller.segmentTexts
    let switching = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    }
    await Task.yield()
    #expect(controller.isSwitchingComparison)
    #expect(try validates("undo:", in: controller))
    undoManager.undo()
    #expect(try controller.segmentTexts != decided)
    undoManager.beginUndoGrouping()
    await switching.value
    undoManager.endUndoGrouping()
    #expect(controller.comparisonOptions.mode == .ignoreAllWhitespace)
    try controller.checkResultIsShownAsModelled()
    // The decision taken back stays taken back: the window shows what the same switch makes of
    // the merge without it.
    let (unchanged, unchangedUndo, _, _) = try await switchedMerge()
    defer { unchanged.window?.close() }
    unchangedUndo.beginUndoGrouping()
    await unchanged.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    unchangedUndo.endUndoGrouping()
    #expect(try controller.segmentTexts == unchanged.segmentTexts)
    #expect(
      controller.presentation.navigation.openConflictCount
        == unchanged.presentation.navigation.openConflictCount)
  }

  @Test func stepThatBringsBackAComparisonWaitsWhateverStepComesLaterInItsGroup()
    async throws
  {
    let (controller, undoManager, _, _) = try await switchedMerge()
    defer { controller.window?.close() }
    // A switch and a decision in one group of undo, which the decision names.
    undoManager.beginUndoGrouping()
    await controller.switchComparison(to: ComparisonOptions(mode: .windowDefault))
    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    controller.perform(.useA)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName != SessionWindowController.switchName)

    let switching = Task {
      await controller.switchComparison(to: ComparisonOptions(mode: .ignoreAllWhitespace))
    }
    await Task.yield()
    #expect(controller.isSwitchingComparison)
    #expect(try !validates("undo:", in: controller))
    // What the Edit menu would let through; undone now, the group would bring back its
    // comparison alongside the switch.
    if try validates("undo:", in: controller) {
      undoManager.undo()
    }
    undoManager.beginUndoGrouping()
    await switching.value
    undoManager.endUndoGrouping()
    #expect(controller.comparisonOptions.mode == .ignoreAllWhitespace)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func blockKeysSoundButActNotWhileUndoBringsBackAComparison() async throws {
    let (controller, undoManager, _, switched) = try await switchedMerge()
    defer { controller.window?.close() }
    let window = try #require(controller.window)
    controller.presentation.setCurrentBlock(controller.presentation.navigation.firstOpenConflict)
    undoManager.undo()
    #expect(controller.isInBlockMode)
    for key in ["3", "\r"] {
      #expect(controller.handleKeyDown(try event(key, in: window)))
    }
    #expect(try controller.segmentTexts == switched, "no decision while it waits")
    #expect(!controller.isInTextMode)
    await controller.comparisonReturn?.value
  }

  @Test func windowClosedWhileUndoBringsBackAComparisonShowsNothingMore() async throws {
    let (controller, undoManager, _, switched) = try await switchedMerge()
    undoManager.undo()
    let returning = try #require(controller.comparisonReturn)
    controller.window?.close()
    await returning.value
    #expect(controller.comparisonOptions.mode == .exact)
    #expect(try controller.segmentTexts == switched)
    #expect(controller.diskWatch.watchedURLs.isEmpty)
  }

  @Test func progressOfABringBackThatTakesAMomentShowsAndIsHeard() async throws {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    // Large enough that making the panes ready takes longer than the delay of the progress.
    let controller = try Windows.controller(
      for: try await SampleMerges.manyBlocks(lineCount: 100_000), undoManager: undoManager)
    defer { controller.window?.close() }
    undoManager.beginUndoGrouping()
    await controller.switchComparison(to: ComparisonOptions(mode: .exact))
    undoManager.endUndoGrouping()
    undoManager.undo()
    let returning = try #require(controller.comparisonReturn)
    let progress = ProgressListener()
    controller.presentation.announce = { text in
      progress.hear(text, showing: controller.showsComparisonProgress)
    }
    await returning.value
    #expect(progress.heardWhileShowing)
    #expect(!controller.showsComparisonProgress)
  }
}

/// Hears what a window tells VoiceOver and whether it said that the files are being compared
/// while its toolbar showed so.
@MainActor
private final class ProgressListener {
  private(set) var heardWhileShowing = false

  func hear(_ text: String, showing: Bool) {
    if text == SessionToolbar.comparingText && showing {
      heardWhileShowing = true
    }
  }
}
