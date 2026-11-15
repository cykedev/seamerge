import AppKit
import MergeModel

extension SessionWindowController {
  /// The ignore rules the comparison of the window should use: those switched on in Settings
  /// while the window uses ignore rules, and none in a merge, which always compares all text.
  var requestedIgnoreRules: [IgnoreRule] {
    ignoreRules(whenUsing: usesIgnoreRules)
  }

  /// The ignore rules the comparison of the window uses if `usesIgnoreRules` says whether the
  /// window uses them.
  private func ignoreRules(whenUsing usesIgnoreRules: Bool) -> [IgnoreRule] {
    guard usesIgnoreRules, presentation.changes.session.kind == .diff else { return [] }
    return settings.ignoreRules.filter(\.isEnabled)
  }

  /// Whether two lists of switched-on rules leave out the same text: whether they have the same
  /// patterns in the same order, whatever their names.
  static func haveTheSameEffect(_ rules: [IgnoreRule], _ others: [IgnoreRule]) -> Bool {
    rules.map(\.pattern) == others.map(\.pattern)
  }

  /// Whether a rule of Settings is switched on and can take effect, which Use Ignore Rules
  /// needs.
  var hasEffectiveIgnoreRule: Bool {
    settings.ignoreRules.contains { $0.isEnabled && $0.problem == nil }
  }

  /// Leaves out the text that the ignore rules of Settings match, or compares all text again,
  /// as a step of undo; the current block stays.
  @objc func toggleIgnoreRules(_ sender: Any?) {
    guard canPerform(.toggleIgnoreRules) else { return }
    Task { await compareWithRequestedRules(usingIgnoreRules: !usesIgnoreRules) }
  }

  /// The help tag of Use Ignore Rules in the window, which says why a merge cannot use it.
  var ignoreRulesHelp: String? {
    guard presentation.changes.session.kind == .merge else {
      return SessionCommand.toggleIgnoreRules.help
    }
    return String(
      localized: "Merges always compare all text.", bundle: .module,
      comment: "Help tag of Compare > Use Ignore Rules in a merge, where it is unavailable.")
  }

  /// Compares anew whenever the ignore rules of Settings change.
  func observeIgnoreRules() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(ignoreRulesDidChange(_:)),
      name: UserSettings.ignoreRulesDidChangeNotification, object: settings)
  }

  @objc private func ignoreRulesDidChange(_ notification: Notification) {
    followIgnoreRules()
  }

  /// Compares anew, as no step of undo, if the comparison does not use the rules the window
  /// should use, such as after they changed in Settings; while another comparison is under way,
  /// the window does so once that is over.
  ///
  /// A rule that was only renamed changes nothing.
  func followIgnoreRules() {
    guard !isSwitchingComparison, showsComparedLines,
      !Self.haveTheSameEffect(presentation.changes.session.ignoreRules, requestedIgnoreRules)
    else { return }
    Task { await compareWithRequestedRules(usingIgnoreRules: nil) }
  }

  /// Whether the window shows the lines of a comparison, not why it cannot.
  private var showsComparedLines: Bool {
    unavailable == nil && binaryMerge == nil && collectionPlaceholder == nil
  }

  /// Compares the files anew with the rules of Settings, or none: if `usingIgnoreRules` is
  /// given, the window then uses ignore rules or not as it says, as a step of undo; otherwise
  /// the window follows the rules of Settings as it uses them, as no step of undo.
  func compareWithRequestedRules(usingIgnoreRules: Bool?) async {
    guard !isSwitchingComparison, showsComparedLines else { return }
    await whileComparingAnew {
      let session = presentation.changes.session
      let uses = usingIgnoreRules ?? usesIgnoreRules
      let rules = ignoreRules(whenUsing: uses)
      guard session.kind == .diff, !Self.haveTheSameEffect(rules, session.ignoreRules) else {
        usesIgnoreRules = uses
        return
      }
      let switched: Session
      do throws(MergeModelError) {
        switched = try await session.recomputed(ignoring: rules)
      } catch {
        await comparisonFailed(error)
        return
      }
      // The undo of the switch takes the window back to whether it used rules before.
      show(switched, result: nil, named: usingIgnoreRules == nil ? nil : Self.switchName)
      usesIgnoreRules = uses
    }
  }
}
