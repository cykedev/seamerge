import Foundation
import MergeModel

/// A comparison that the window showed, with all that undo and redo bring back of it.
struct ShownComparison {
  /// The comparison of the files, with the result of a merge.
  var shown: ShownSession

  /// Whether the window used the ignore rules of Settings.
  var usesIgnoreRules: Bool
}

/// Compares the files of a session window anew, one comparison at a time, and brings back an
/// earlier comparison as a step of undo or redo.
///
/// Every way to compare anew runs as the one comparison under way: a switch of the comparison
/// mode or the ignore rules as soon as its task runs, and a return of undo or redo at once. Once
/// it takes a moment, the delegate says so. The switcher decides nothing about what to compare;
/// the window does, and shows the outcome.
///
/// The comparison shown before the one in view keeps the texts of its panes, so that undo
/// brings it back at once; the one shown before that lets go of them, unless it is shown again.
/// Every switch would keep a copy of the files otherwise, for as long as the window stays open.
@MainActor
final class ComparisonSwitcher {
  /// Shows a comparison brought back and what the comparison under way changes.
  weak var delegate: (any ComparisonSwitcherDelegate)?

  /// Whether the files are being compared anew.
  private(set) var isComparing = false

  /// The return to an earlier comparison that undo or redo brings back, while the window makes
  /// it ready away from the main actor; until it shows, the window takes no edit, no command
  /// of the lines and no undo or redo.
  ///
  /// Once the window shows another file or closes, the return is cancelled but stays until its
  /// task ends.
  private(set) var bringingBack: Task<Void, Never>?

  /// The comparison the window showed before the one it shows now.
  private var shownBefore: Session?

  /// The timer that says that the comparison under way takes a moment.
  private var progressTimer: Timer?

  private let undoManager: UndoManager
  private let presentation: SessionPresentation
  private let resultUndo: ResultUndo

  /// The key of the user info by which the undo manager marks a group that brings back an
  /// earlier comparison.
  static let bringsBackComparison = UndoManager.UserInfoKey("bringsBackComparison")

  /// How long a comparison runs before the delegate says that it is under way.
  static let progressDelay: TimeInterval = 0.15

  /// Creates the switcher of a window whose steps of undo go to `undoManager`, which shows
  /// its comparisons in `presentation`, and whose runs of typing `resultUndo` ends.
  init(undoManager: UndoManager, presentation: SessionPresentation, resultUndo: ResultUndo) {
    self.undoManager = undoManager
    self.presentation = presentation
    self.resultUndo = resultUndo
  }

  /// Carries out `body`, which compares the files anew, as the one comparison under way.
  ///
  /// - Precondition: No other comparison is under way.
  func whileComparingAnew(_ body: () async -> Void) async {
    beginComparing()
    await body()
    endComparing()
  }

  /// Makes the comparison that begins now the one under way, which the delegate says once it
  /// takes a moment.
  ///
  /// - Precondition: No other comparison is under way.
  private func beginComparing() {
    precondition(!isComparing, "One comparison runs at a time")
    isComparing = true
    let progressTimer = Timer(timeInterval: Self.progressDelay, repeats: false) { [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated {
        guard let self else { return }
        self.delegate?.comparisonSwitcherTakesAMoment(self)
      }
    }
    RunLoop.main.add(progressTimer, forMode: .common)
    self.progressTimer = progressTimer
  }

  /// Ends the comparison under way.
  private func endComparing() {
    progressTimer?.invalidate()
    progressTimer = nil
    isComparing = false
    delegate?.comparisonSwitcherDidEnd(self)
  }

  /// Notes that the window shows `session` in place of `previous`: `previous` keeps the texts
  /// of its panes, and the comparison shown before it lets go of them unless `session` shares
  /// them.
  func keepShownBefore(_ previous: Session, showing session: Session) {
    if let older = shownBefore, !older.rowLayout.sharesDisplayTexts(with: session.rowLayout) {
      older.rowLayout.letGoOfDisplayTexts()
    }
    shownBefore = previous
  }

  /// Forgets the comparison shown before, as the window shows another file, whose steps of undo
  /// start anew.
  func forgetShownBefore() {
    shownBefore = nil
  }

  /// Registers the step that shows `comparison` again, named `name`: on the undo stack, or on
  /// the redo stack while undoing.
  func registerReturn(to comparison: ShownComparison, named name: String) {
    undoManager.registerUndo(withTarget: self) { switcher in
      switcher.bringBack(comparison, named: name)
    }
    undoManager.setActionName(name)
    // The mark stays with the group of the step, whatever names a later step in it gives it.
    undoManager.setActionUserInfoValue(true, forKey: Self.bringsBackComparison)
  }

  /// Shows `comparison` again, as undo or redo of a switch or a reload: registers the step that
  /// comes back to what the window shows now at once, as the undo manager asks, and becomes the
  /// comparison under way at once, then makes the panes ready away from the main actor and has
  /// the delegate show them.
  ///
  /// Until then the window takes no edit and no command of the lines, nor another undo or redo:
  /// each would change what the step registered for this comparison, which it brings back as it
  /// was. Once the window shows another file or closes meanwhile, it shows nothing.
  ///
  /// - Precondition: No other comparison is under way.
  private func bringBack(_ comparison: ShownComparison, named name: String) {
    guard let delegate else { return }
    resultUndo.endTypingRun()
    registerReturn(to: delegate.shownComparison(for: self), named: name)
    presentation.acceptsEdits = false
    beginComparing()
    bringingBack = Task {
      var prepared: PreparedSession?
      while prepared == nil, !Task.isCancelled {
        prepared = await presentation.prepare(comparison.shown)
      }
      if let prepared, !Task.isCancelled {
        self.delegate?.comparisonSwitcher(self, bringsBack: comparison, as: prepared)
      }
      bringingBack = nil
      presentation.acceptsEdits = true
      endComparing()
    }
    delegate.comparisonSwitcherDidBeginBringingBack(self)
  }

  /// Stops bringing back an earlier comparison, as the window shows another file or closes.
  func stopBringingBack() {
    bringingBack?.cancel()
  }
}
