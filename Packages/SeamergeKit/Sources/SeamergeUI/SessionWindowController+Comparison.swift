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
    isSwitchingComparison = true
    let progressTimer = Timer(timeInterval: Self.progressDelay, repeats: false) { [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated {
        self?.showsComparisonProgress = true
        self?.stateDidChange()
      }
    }
    RunLoop.main.add(progressTimer, forMode: .common)
    defer {
      progressTimer.invalidate()
      isSwitchingComparison = false
      showsComparisonProgress = false
      stateDidChange()
      lookAtFilesAgainIfAsked()
    }
    let session = presentation.changes.session
    let switched: Session
    do {
      switched = try await session.recomputed(options: options)
    } catch {
      await comparisonFailed(error)
      return
    }
    guard let result = presentation.result else {
      show(switched, result: nil, named: Self.switchName)
      return
    }
    let modeSwitch = result.document.planSwitching(to: switched, text: result.text)
    if modeSwitch.discardedDecisionCount > 0 {
      guard let window,
        await prompts.confirmDiscarding(modeSwitch.discardedDecisionCount, in: window)
      else { return }
    }
    var document = result.document
    _ = document.apply(modeSwitch.plan, replacedTexts: [result.text])
    show(
      document.session,
      result: ResultState(
        document: document, text: modeSwitch.plan.replacements.map(\.text).joined()),
      named: Self.switchName)
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

  /// Shows `session` with `result`, the result of a merge, in place of what the window shows
  /// now, with the headers of its files, as a step of undo named `name` that shows that again.
  func show(_ session: Session, result: ResultState?, named name: String) {
    let previous = (presentation.changes.session, presentation.result)
    typingRun = nil
    presentation.show(session, result: result)
    presentation.show(
      Dictionary(
        uniqueKeysWithValues: session.roles.map { role in
          (role, SideHeader(role: role, session: session, context: context))
        }))
    sessionDidChange()
    sessionUndoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.show(previous.0, result: previous.1, named: name) }
    }
    sessionUndoManager.setActionName(name)
    showResultFormat()
    watchFiles()
    stateDidChange()
  }

  /// What Undo calls the switch to another comparison mode.
  private static var switchName: String {
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
