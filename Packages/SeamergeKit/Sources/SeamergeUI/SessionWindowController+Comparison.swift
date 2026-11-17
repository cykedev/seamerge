import AppKit
import MergeModel
import os

extension SessionWindowController {
  /// How the window compares its files: the comparison mode and, in a merge, the merge
  /// strategy.
  public var comparisonOptions: ComparisonOptions {
    presentation.changes.session.options
  }

  /// Compares the files anew with `options` and shows the outcome, keeping each decision of a
  /// merge whose block has the same lines in the new comparison, and the line of B where it is.
  ///
  /// The window shows the old comparison until the new one is ready. If decisions would be lost,
  /// a sheet asks first. The switch is a single step of undo. While one switch runs, another one
  /// does nothing.
  public func switchComparison(to options: ComparisonOptions) async {
    guard options != comparisonOptions, !isSwitchingComparison else { return }
    await whileComparingAnew {
      let switched: Session
      do throws(MergeModelError) {
        switched = try await presentation.changes.session.recomputed(options: options)
      } catch {
        await comparisonFailed(error)
        return
      }
      guard presentation.result != nil else {
        show(await prepared(switched, result: nil), named: Self.switchName)
        return
      }
      // The user may decide or type while the new comparison is made ready; it then starts
      // over from the result as it is now.
      while let result = presentation.result {
        let modeSwitch = await Self.switching(result, to: switched)
        if modeSwitch.discardedDecisionCount > 0 {
          guard let window,
            await prompts.confirmDiscarding(modeSwitch.discardedDecisionCount, in: window)
          else { return }
          // Asking took a moment; a decision made meanwhile goes into the switch as well.
          guard isShowing(result) else { continue }
        }
        let prepared = await prepared(modeSwitch.session, result: modeSwitch.result)
        guard isShowing(result) else { continue }
        show(prepared, named: Self.switchName)
        return
      }
    }
  }

  /// What switching `result` to `session`, the same files compared anew, makes of it: the
  /// session and the result with each decision that keeps its block, and how many decisions it
  /// discards; worked out away from the main actor.
  @concurrent
  private static func switching(
    _ result: ResultState, to session: Session
  ) async -> (session: Session, result: ResultState, discardedDecisionCount: Int) {
    let modeSwitch = result.document.planSwitching(to: session, text: result.text)
    var document = result.document
    _ = document.apply(modeSwitch.plan, replacedTexts: [result.text])
    return (
      document.session,
      ResultState(document: document, text: modeSwitch.plan.replacements.map(\.text).joined()),
      modeSwitch.discardedDecisionCount
    )
  }

  /// Whether the window shows `result` as the result of its merge, unchanged since.
  func isShowing(_ result: ResultState) -> Bool {
    guard let current = presentation.result else { return false }
    return current.text == result.text && current.document.segments == result.document.segments
  }

  /// What the panes show for `session` with `result`, made away from the main actor for the
  /// setup of the panes once it is ready; made anew while the user changes the setup
  /// meanwhile, as by showing all lines in another arrangement.
  func prepared(_ session: Session, result: ResultState?) async -> PreparedSession {
    while true {
      if let prepared = await presentation.prepare(session, result: result) {
        return prepared
      }
    }
  }

  /// Carries out `body`, which compares the files anew, as the one comparison under way: the
  /// toolbar says so once it takes a moment, and afterwards the window looks at what changed
  /// meanwhile, its files and the ignore rules of Settings.
  ///
  /// - Precondition: No other comparison is under way.
  func whileComparingAnew(_ body: () async -> Void) async {
    let progressTimer = beginComparingAnew()
    await body()
    endComparingAnew(progressTimer)
  }

  /// Makes the comparison that begins now the one under way, whose progress the toolbar shows
  /// and VoiceOver hears once it takes a moment, with the timer that shows it.
  ///
  /// Every way to compare anew begins here, a switch or a reload as soon as its task runs, undo
  /// and redo at once; each of them does nothing, or waits, while another is under way.
  ///
  /// - Precondition: No other comparison is under way.
  private func beginComparingAnew() -> Timer {
    precondition(!isSwitchingComparison, "One comparison runs at a time")
    isSwitchingComparison = true
    let progressTimer = Timer(timeInterval: Self.progressDelay, repeats: false) { [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated {
        guard let controller = self else { return }
        controller.showsComparisonProgress = true
        controller.stateDidChange()
        controller.presentation.announce(SessionToolbar.comparingText)
      }
    }
    RunLoop.main.add(progressTimer, forMode: .common)
    return progressTimer
  }

  /// Ends the comparison under way, which `progressTimer` shows the progress of, and looks at
  /// what changed meanwhile, unless the window closed.
  private func endComparingAnew(_ progressTimer: Timer) {
    progressTimer.invalidate()
    isSwitchingComparison = false
    showsComparisonProgress = false
    stateDidChange()
    guard !hasFinished else { return }
    lookAtFilesAgainIfAsked()
    followIgnoreRules()
  }

  /// Compares lines byte for byte.
  @objc func compareExactly(_ sender: Any?) {
    switchMode(to: .exact)
  }

  /// Compares lines without their line endings.
  @objc func ignoreLineEndings(_ sender: Any?) {
    switchMode(to: .ignoreLineEndings)
  }

  /// Compares lines as equal where they differ only in the amount of whitespace.
  @objc func ignoreWhitespaceChanges(_ sender: Any?) {
    switchMode(to: .ignoreWhitespaceAmount)
  }

  /// Compares lines without any of their whitespace.
  @objc func ignoreAllWhitespace(_ sender: Any?) {
    switchMode(to: .ignoreAllWhitespace)
  }

  private func switchMode(to mode: ComparisonMode) {
    var options = comparisonOptions
    options.mode = mode
    Task { await switchComparison(to: options) }
  }

  /// Puts the two files of a comparison the other way round, with their headers, colors and
  /// markers; the current change and the place at the reading line stay.
  ///
  /// It changes only how the files are shown, so it is no step of undo.
  @objc func swapSides(_ sender: Any?) {
    guard canPerform(.swapSides) else { return }
    presentation.swapSides()
    sessionDidChange()
    stateDidChange()
  }

  /// Shows `prepared`, made for the same files compared anew, in place of what the window shows
  /// now, with the headers of its files, as a step of undo named `name` that shows that again,
  /// or as no step of undo without a name.
  ///
  /// Undo brings back whether the window used ignore rules as well, and then compares anew if
  /// the rules of Settings changed meanwhile. The language of the code is recognized anew, since
  /// a file read again may start with another first line.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func show(_ prepared: PreparedSession, named name: String?) {
    let previous = shownComparison
    let session = prepared.changes.session
    typingRun = nil
    presentation.showComparedAnew(prepared)
    presentation.show(
      Dictionary(
        uniqueKeysWithValues: session.roles.map { role in
          (role, SideHeader(role: role, session: session, context: context))
        }))
    detectedLanguage = SessionSyntax.language(of: session, resultURL: context.resultURL)
    presentation.colorSyntax(as: syntaxLanguage)
    sessionDidChange()
    if let name {
      registerReturn(to: previous, named: name)
    }
    showResultFormat()
    watchFiles()
    stateDidChange()
  }

  /// The comparison that the window shows now, as undo and redo bring it back.
  private var shownComparison: ShownComparison {
    ShownComparison(
      session: presentation.changes.session, result: presentation.result,
      usesIgnoreRules: usesIgnoreRules)
  }

  /// Registers the step that shows `comparison` again, named `name`: on the undo stack, or on
  /// the redo stack while undoing.
  private func registerReturn(to comparison: ShownComparison, named name: String) {
    sessionUndoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.bringBack(comparison, named: name) }
    }
    sessionUndoManager.setActionName(name)
    // The mark stays with the group of the step, whatever names a later step in it gives it.
    sessionUndoManager.setActionUserInfoValue(true, forKey: Self.bringsBackComparison)
  }

  /// The key of the user info by which the undo manager marks a group that brings back an
  /// earlier comparison.
  static let bringsBackComparison = UndoManager.UserInfoKey("bringsBackComparison")

  /// Shows `comparison` again, as undo or redo of a switch or a reload: registers the step that
  /// comes back to what the window shows now at once, as the undo manager asks, and becomes the
  /// comparison under way at once, then makes the panes ready away from the main actor and
  /// shows them.
  ///
  /// Until then the window takes no edit and no command, nor another undo or redo: each would
  /// change what the step registered for this comparison, which it brings back as it was. Once
  /// the window shows another file or closes meanwhile, it shows nothing.
  ///
  /// - Precondition: No other comparison is under way.
  private func bringBack(_ comparison: ShownComparison, named name: String) {
    typingRun = nil
    registerReturn(to: shownComparison, named: name)
    presentation.acceptsEdits = false
    let progressTimer = beginComparingAnew()
    comparisonReturn = Task {
      var prepared: PreparedSession?
      while prepared == nil, !Task.isCancelled {
        prepared = await presentation.prepare(comparison.session, result: comparison.result)
      }
      if let prepared, !Task.isCancelled {
        show(prepared, named: nil)
        usesIgnoreRules = comparison.usesIgnoreRules
      }
      comparisonReturn = nil
      presentation.acceptsEdits = true
      endComparingAnew(progressTimer)
    }
    stateDidChange()
  }

  /// Stops bringing back an earlier comparison, as the window shows another file or closes.
  func stopBringingBack() {
    comparisonReturn?.cancel()
  }

  /// Whether undo or redo of a group of steps can act now, which `bringsBack` tells whether it
  /// brings back an earlier comparison: none while the window brings one back, and none that
  /// brings one back while it compares or reloads its files; the steps of decisions and typing
  /// can, since the comparison under way starts over from the result they leave, as after a
  /// decision.
  func allowsStep(bringingBackAComparison bringsBack: Bool) -> Bool {
    guard comparisonReturn == nil else { return false }
    return !bringsBack || !(isSwitchingComparison || isReloading)
  }

  /// What Undo calls the switch to another comparison mode.
  static var switchName: String {
    String(
      localized: "Change Comparison", bundle: .module,
      comment: "Undo menu: the switch to another comparison mode or merge strategy.")
  }

  /// Tells that the files could not be compared anew, and keeps the comparison shown now.
  func comparisonFailed(_ error: MergeModelError) async {
    Self.logger.error("Comparing anew failed: \(error, privacy: .public)")
    guard let window else { return }
    await prompts.reportFailedComparison(in: window)
  }

  /// How long a comparison runs before the toolbar says that it is under way.
  static let progressDelay: TimeInterval = 0.15

  static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")
}

/// A comparison that the window showed, with all that undo and redo bring back of it.
private struct ShownComparison {
  /// The comparison of the files.
  var session: Session

  /// The result of a merge, or `nil` for a comparison of two files.
  var result: ResultState?

  /// Whether the window used the ignore rules of Settings.
  var usesIgnoreRules: Bool
}
