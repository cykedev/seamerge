import AppKit
import MergeModel

/// The undo of the result of a merge: each step restores text and segments together, a run of
/// typing is one step, and so is a replacement of the search.
///
/// The undo manager of the window is the only owner of the steps. Every other step of the window
/// goes to the same manager, and any of them, as well as any command of a menu, ends a run of
/// typing.
@MainActor
final class ResultUndo {
  private let undoManager: UndoManager
  private let presentation: SessionPresentation

  /// The time now, which tells when typing paused.
  private let now: () -> ContinuousClock.Instant

  /// The typing that the last step of undo takes back, as long as further typing joins it.
  private var typingRun: TypingRun?

  /// The steps of the replacement of the search under way, which become one step of undo once
  /// it is over, or `nil` while the search replaces nothing.
  private var replacementSteps: [UndoStep]?

  private var observations: [NotificationCenter.ObservationToken] = []

  /// Keeps the steps of the result of `presentation` in `undoManager`; `now` tells the time,
  /// which ends a run of typing after a pause.
  init(
    undoManager: UndoManager, presentation: SessionPresentation,
    now: @escaping () -> ContinuousClock.Instant
  ) {
    self.undoManager = undoManager
    self.presentation = presentation
    self.now = now
    // A step of undo of anything else opens a group of the undo manager, which the continuation
    // of a run never does: it extends the step that the run registered once.
    let center = NotificationCenter.default
    observations = [
      center.addObserver(of: undoManager, for: .didOpenUndoGroup) { [weak self] _ in
        self?.typingRun = nil
      },
      center.addObserver(of: NSMenu.self, for: .didSendAction) { [weak self] _ in
        self?.typingRun = nil
      },
    ]
  }

  isolated deinit {
    for observation in observations {
      NotificationCenter.default.removeObserver(observation)
    }
  }

  /// Carries out `plan`, a plan of the result document, as one step of undo named `name`.
  func carryOut(_ plan: EditPlan, named name: String) {
    guard !plan.isEmpty else { return }
    typingRun = nil
    guard let step = presentation.carryOut(plan) else { return }
    register(step, named: name)
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
    undoManager.registerUndo(withTarget: self) { undo in undo.takeBack(run.step, named: name) }
    undoManager.setActionName(name)
    // After the registration, which may open a group of undo and so end any run.
    typingRun = run
  }

  /// Ends the run of typing, as anything but typing happens that the undo manager does not see
  /// open a group, such as a step of the window registered within a group already open.
  func endTypingRun() {
    typingRun = nil
  }

  /// Ends the run of typing if the insertion point moved to `selection` by anything but typing
  /// on from where the run left it.
  func endTypingRun(unlessContinuedAt selection: NSRange) {
    guard let run = typingRun, selection != NSRange(location: run.caret, length: 0) else { return }
    typingRun = nil
  }

  /// Ends the run of typing and gathers the steps of the replacement of the search that begins,
  /// which the result reports as typing, into one step of their own.
  func beginReplacement() {
    typingRun = nil
    replacementSteps = []
  }

  /// Registers the steps of the replacement of the search that ends as one step of undo named
  /// `name`.
  func endReplacement(named name: String) {
    let steps = replacementSteps ?? []
    replacementSteps = nil
    typingRun = nil
    guard let first = steps.first else { return }
    guard let joined = steps.dropFirst().reduce(Optional(first), { $0?.coalesced(with: $1) })
    else {
      preconditionFailure("The result reports every replacement as typing, which always joins")
    }
    register(joined, named: name)
  }

  /// Registers the step that takes `step` back, under `name`: on the undo stack, or on the redo
  /// stack while undoing.
  private func register(_ step: UndoStep, named name: String) {
    undoManager.registerUndo(withTarget: self) { undo in undo.takeBack(step, named: name) }
    undoManager.setActionName(name)
  }

  /// Takes `step` back, which registers the step that does it again, and tells VoiceOver what
  /// was undone or redone.
  private func takeBack(_ step: UndoStep, named name: String) {
    typingRun = nil
    let isUndoing = undoManager.isUndoing
    guard let undone = presentation.carryOut(step.undoPlan) else { return }
    register(undone, named: name)
    presentation.announceOutcome(
      isUndoing
        ? undoManager.undoMenuTitle(forUndoActionName: name)
        : undoManager.redoMenuTitle(forUndoActionName: name))
  }

  /// The pause after which typing starts a new step of undo.
  private static let typingPause: Duration = .seconds(2)

  /// What Undo calls a run of typing.
  private static let typingName = String(
    localized: "Typing", bundle: .module, comment: "Undo menu: text typed in the result.")
}

/// A run of typing in the result, which one step of undo takes back whole.
///
/// The step of undo is registered once, when the run starts, and reads the run when it is taken;
/// typing that continues the run extends it.
@MainActor
private final class TypingRun {
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
