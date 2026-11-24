import AppKit
public import MergeModel
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
    guard options != comparisonOptions, !comparisonSwitcher.isComparing else { return }
    await comparisonSwitcher.whileComparingAnew {
      let switched: Session
      do throws(MergeModelError) {
        switched = try await presentation.changes.session.recomputed(options: options)
      } catch {
        await comparisonFailed(error)
        return
      }
      guard presentation.result != nil else {
        show(await prepared(.comparison(switched)), named: Self.switchName)
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
        let prepared = await prepared(.merge(modeSwitch.result))
        guard isShowing(result) else { continue }
        show(prepared, named: Self.switchName)
        return
      }
    }
  }

  /// What switching `result` to `session`, the same files compared anew, makes of it: the
  /// result of the new merge with each decision that keeps its block, and how many decisions it
  /// discards; worked out away from the main actor.
  @concurrent
  private static func switching(
    _ result: ResultState, to session: Session
  ) async -> (result: ResultState, discardedDecisionCount: Int) {
    let modeSwitch = result.document.planSwitching(to: session, text: result.text)
    var document = result.document
    _ = document.apply(modeSwitch.plan, replacedTexts: [result.text])
    return (
      ResultState(document: document, text: modeSwitch.plan.replacements.map(\.text).joined()),
      modeSwitch.discardedDecisionCount
    )
  }

  /// Whether the window shows `result` as the result of its merge, unchanged since.
  func isShowing(_ result: ResultState) -> Bool {
    guard let current = presentation.result else { return false }
    return current.text == result.text && current.document.segments == result.document.segments
  }

  /// What the panes show for `shown`, made away from the main actor for the setup of the panes
  /// once it is ready; made anew while the user changes the setup meanwhile, as by showing all
  /// lines in another arrangement.
  ///
  /// With `collapsed`, the panes collapse its runs, else every run that collapses in a new
  /// window.
  func prepared(_ shown: ShownSession, collapsed: CollapsedRows? = nil) async -> PreparedSession {
    while true {
      if let prepared = await presentation.prepare(shown, collapsed: collapsed) {
        return prepared
      }
    }
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
  /// The comparison shown before keeps the texts of its panes, so that undo brings it back at
  /// once; the one shown before that lets go of them, unless it is shown again, and undo lays
  /// them out anew when it brings it back. Every switch would keep a copy of the files
  /// otherwise, for as long as the window stays open.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func show(_ prepared: PreparedSession, named name: String?) {
    show(prepared, named: name) {
      presentation.showComparedAnew(prepared)
    }
  }

  /// Shows `prepared` as ``show(_:named:)`` does, with `placing` putting it in the panes; the
  /// step of undo takes back `copy` or carries it out again, if it is one.
  ///
  /// - Precondition: `prepared` was made for the setup of the panes now.
  func show(
    _ prepared: PreparedSession, named name: String?, copy: CopyReturn? = nil,
    placing: () -> Void
  ) {
    let previous = shownComparison
    let session = prepared.changes.session
    resultUndo.endTypingRun()
    placing()
    if !Self.haveSameContent(previous.shown.session.inputs, session.inputs) {
      workKeeper?.keepWork(of: session.inputs)
    }
    comparisonSwitcher.keepShownBefore(previous.shown.session, showing: session)
    presentation.show(SideHeader.headers(of: session, context: context))
    detectedLanguage = SessionSyntax.language(of: session, context: context)
    presentation.colorSyntax(as: syntaxLanguage)
    sessionDidChange()
    if let name {
      comparisonSwitcher.registerReturn(to: previous, named: name, copy: copy)
    }
    showResultFormat()
    watchFiles()
    workDidChange()
    stateDidChange()
  }

  /// Whether `first` and `second` hold the same bytes in every role, as files compared anew in
  /// another mode do, and files reloaded or changed do not.
  private static func haveSameContent(
    _ first: Session.Inputs<SourceFile>, _ second: Session.Inputs<SourceFile>
  ) -> Bool {
    Role.allCases.allSatisfy { first[$0]?.bytes == second[$0]?.bytes }
  }

  /// The comparison that the window shows now, as undo and redo bring it back.
  private var shownComparison: ShownComparison {
    ShownComparison(
      shown: presentation.shown, usesIgnoreRules: usesIgnoreRules,
      currentBlock: presentation.currentBlock, blockAfterPlace: presentation.blockAfterPlace,
      collapsed: presentation.collapsed)
  }

  /// Whether undo or redo of a group of steps can act now, which `bringsBack` tells whether it
  /// brings back an earlier comparison: none while the window brings one back, and none that
  /// brings one back while it compares or reloads its files; the steps of decisions and typing
  /// can, since the comparison under way starts over from the result they leave, as after a
  /// decision.
  func allowsStep(bringingBackAComparison bringsBack: Bool) -> Bool {
    guard comparisonSwitcher.bringingBack == nil else { return false }
    return !bringsBack || !(comparisonSwitcher.isComparing || diskWatch.isReloading)
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

  nonisolated static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")
}

extension SessionWindowController: ComparisonSwitcherDelegate {
  func shownComparison(for switcher: ComparisonSwitcher) -> ShownComparison {
    shownComparison
  }

  func comparisonSwitcher(
    _ switcher: ComparisonSwitcher, bringsBack comparison: ShownComparison,
    as prepared: PreparedSession, copy: CopyReturn?
  ) {
    if let copy {
      show(prepared, named: nil) {
        presentation.showCopied(
          prepared, keepingTheLineOf: copy.source, current: comparison.currentBlock,
          before: comparison.blockAfterPlace)
      }
      presentation.announce(
        copy.copiesAgain
          ? Self.copiedAnnouncement(to: copy.targetName, leaving: presentation.changes.blocks.count)
          : Self.restoredAnnouncement)
    } else {
      show(prepared, named: nil)
    }
    usesIgnoreRules = comparison.usesIgnoreRules
  }

  /// Takes the presses from the buttons at the seams while the files are compared anew.
  func comparisonSwitcherDidBegin(_ switcher: ComparisonSwitcher) {
    updateCopyControls()
  }

  func comparisonSwitcherDidBeginBringingBack(_ switcher: ComparisonSwitcher) {
    stateDidChange()
  }

  /// Shows the progress of the comparison in the toolbar, and tells VoiceOver.
  func comparisonSwitcherTakesAMoment(_ switcher: ComparisonSwitcher) {
    showsComparisonProgress = true
    stateDidChange()
    presentation.announce(SessionToolbar.comparingText)
  }

  /// Looks at what changed meanwhile, the files and the ignore rules of Settings, unless the
  /// window closed.
  func comparisonSwitcherDidEnd(_ switcher: ComparisonSwitcher) {
    showsComparisonProgress = false
    stateDidChange()
    guard !hasFinished else { return }
    diskWatch.lookAgainIfAsked()
    followIgnoreRules()
  }
}
