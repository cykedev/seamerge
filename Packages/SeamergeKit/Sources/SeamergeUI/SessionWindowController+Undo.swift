import AppKit
import MergeModel

/// A run of typing in the result, which one step of undo takes back whole.
///
/// The step of undo is registered once, when the run starts, and reads the run when it is taken;
/// typing that continues the run extends it.
@MainActor
final class TypingRun {
  /// The step that takes the whole run back.
  var step: UndoStep

  /// Where the insertion point stands after the run, in the result pane's text.
  var caret: Int

  /// When the user typed last.
  var lastTyped: ContinuousClock.Instant

  init(step: UndoStep, caret: Int, lastTyped: ContinuousClock.Instant) {
    self.step = step
    self.caret = caret
    self.lastTyped = lastTyped
  }
}

/// The undo of the result: the window's undo manager is its only owner, and each step restores
/// text and segments together.
extension SessionWindowController {
  /// Carries out `plan`, a plan of the result document, as one step of undo named `name`.
  func carryOut(_ plan: EditPlan, named name: String) {
    guard !plan.isEmpty else { return }
    typingRun = nil
    registerUndo(of: presentation.carryOut(plan), named: name)
  }

  /// Takes `step` of typing over into the run of typing it continues, or starts a run with it;
  /// during a replacement of the search, into the steps of the replacement.
  ///
  /// Typing continues the run that the last step of undo takes back while it starts where the
  /// run left the insertion point, within two seconds of the last key; a command, any other step
  /// of undo, a move of the insertion point or a pause ends the run.
  ///
  /// - Parameters:
  ///   - range: The range of the result pane's text that the typing replaced.
  ///   - caret: The insertion point after the typing.
  func recordTyping(_ step: UndoStep, at range: Range<Int>, caret: Int) {
    if replacementSteps != nil {
      replacementSteps?.append(step)
      return
    }
    let time = now()
    if let run = typingRun, time - run.lastTyped < Self.typingPause,
      run.caret == range.lowerBound || run.caret == range.upperBound,
      let joined = run.step.coalesced(with: step)
    {
      run.step = joined
      run.caret = caret
      run.lastTyped = time
      return
    }
    let run = TypingRun(step: step, caret: caret, lastTyped: time)
    let name = Self.typingName
    sessionUndoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.takeBack(run.step, named: name) }
    }
    sessionUndoManager.setActionName(name)
    // After the registration, which may open a group of undo and so end any run.
    typingRun = run
  }

  /// Ends the run of typing whenever anything but typing happens: any change that makes a step
  /// of undo, among them the commands, a switch of the comparison, undo and redo, and any command
  /// of a menu.
  ///
  /// A step of undo of anything else opens a group of the undo manager, which the continuation
  /// of a run never does: it extends the step that the run registered once.
  func observeStepsOfUndo() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(otherStepDidBegin(_:)),
      name: .NSUndoManagerDidOpenUndoGroup, object: sessionUndoManager)
    center.addObserver(
      self, selector: #selector(otherStepDidBegin(_:)), name: NSMenu.didSendActionNotification,
      object: nil)
  }

  @objc private func otherStepDidBegin(_ notification: Notification) {
    typingRun = nil
  }

  /// Ends the run of typing if the insertion point moved to `selection` by anything but typing
  /// on from where the run left it.
  func endTypingRun(unlessContinuedAt selection: NSRange) {
    guard let run = typingRun, selection != NSRange(location: run.caret, length: 0) else { return }
    typingRun = nil
  }

  /// Registers the step that takes `step` back, under `name`: on the undo stack, or on the redo
  /// stack while undoing.
  func registerUndo(of step: UndoStep, named name: String) {
    sessionUndoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.takeBack(step, named: name) }
    }
    sessionUndoManager.setActionName(name)
  }

  /// Takes `step` back, which registers the step that does it again, and tells VoiceOver what
  /// was undone or redone.
  private func takeBack(_ step: UndoStep, named name: String) {
    typingRun = nil
    let isUndoing = sessionUndoManager.isUndoing
    registerUndo(of: presentation.carryOut(step.undoPlan), named: name)
    announceOutcome(
      isUndoing
        ? sessionUndoManager.undoMenuTitle(forUndoActionName: name)
        : sessionUndoManager.redoMenuTitle(forUndoActionName: name))
  }

  /// Tells VoiceOver `outcome`, what a command or undo did, with the open conflicts that are
  /// left, in the words of the toolbar.
  func announceOutcome(_ outcome: String) {
    guard let document = presentation.result?.document else { return }
    let count = SessionToolbar.countText(
      openConflictCount: document.openConflictCount,
      hasConflicts: presentation.changes.blocks.contains { $0.kind == .conflict })
    presentation.announce(
      String(
        localized: "\(outcome). \(count)", bundle: .module,
        comment: "VoiceOver after a decision, such as Chosen: B. 2 Conflicts Left."))
  }

  /// Tells VoiceOver how changed block `block` stands after a command, with the open
  /// conflicts that are left.
  func announceState(ofBlock block: Int) {
    guard let state = presentation.decisionColumn?.decisions[block]?.state.spokenName else {
      return
    }
    announceOutcome(state)
  }

  /// The pause after which typing starts a new step of undo.
  static let typingPause: Duration = .seconds(2)

  /// What Undo calls a run of typing.
  static let typingName = String(
    localized: "Typing", bundle: .module, comment: "Undo menu: text typed in the result.")
}
