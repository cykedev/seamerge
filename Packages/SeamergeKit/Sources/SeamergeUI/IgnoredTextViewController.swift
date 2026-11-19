import AppKit
import MergeModel
import PaneKit

/// The page Ignored Text of Settings: the table of the ignore rules, the buttons that add,
/// remove and duplicate them, and the field in which the selected rule is tried.
///
/// The rules that come with the app stand at the top and can only be switched on and off; the
/// user's own rules follow. Each change is kept in the settings at once and is a step of undo of
/// the window.
@MainActor
final class IgnoredTextViewController: NSViewController {
  /// The settings that keep the rules.
  let settings: UserSettings

  /// The table of the rules.
  let tableView = IgnoreRuleTableView()

  /// The buttons that add a rule and remove the selected one.
  let addButton: NSButton
  let removeButton: NSButton

  /// The button that makes an own copy of the selected rule.
  let duplicateButton: NSButton

  /// The note below the table while the user has no rule of their own.
  let note: NSTextField

  /// The label above the field in which the selected rule is tried, which says what the field
  /// is for once text fills it.
  let trialLabel: NSTextField

  /// The field in which the selected rule is tried.
  let trialField: RuleTrialField

  /// Why the selected rule leaves nothing out, below the field, or empty.
  let reasonLabel: NSTextField

  /// The trial of the selected rule on the text of the field while it runs.
  private(set) var trialTask: Task<Void, Never>?

  /// The patterns that took too long in a trial, which their rows warn about.
  private(set) var slowPatterns: Set<String> = []

  /// The pattern typed into the field of the selected rule while it is edited, which the trial
  /// takes before it is kept.
  private var typedPattern: String?

  /// Whether the table shows the rules anew, which ends an edit without keeping it.
  private(set) var isReloadingRules = false

  /// The columns of the table, by what they show.
  enum Column: String, CaseIterable {
    case isEnabled
    case name
    case pattern

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
  }

  /// Creates the page for the rules of `settings`, with the marks of the trial drawn with
  /// `displayOptions`.
  init(settings: UserSettings, displayOptions: DisplayOptions) {
    self.settings = settings
    addButton = NSButton(image: Self.symbol("plus"), target: nil, action: nil)
    removeButton = NSButton(image: Self.symbol("minus"), target: nil, action: nil)
    duplicateButton = NSButton(
      title: String(
        localized: "Duplicate", bundle: .module,
        comment: "Settings: button and context menu item that copy an ignore rule."),
      target: nil, action: nil)
    note = NSTextField(
      wrappingLabelWithString: String(
        localized: "Add a pattern for text that changes on every build, such as a date.",
        bundle: .module, comment: "Settings: note below the ignore rules while none is the user’s.")
    )
    trialLabel = NSTextField(
      labelWithString: String(
        localized: "Try the selected rule:", bundle: .module,
        comment: "Settings: label above the field in which an ignore rule is tried."))
    trialField = RuleTrialField(
      label: trialLabel.stringValue, font: settings.codeFont(ofSize: NSFont.systemFontSize),
      markColor: displayOptions.theme.ignoredDifferenceFill)
    reasonLabel = NSTextField(wrappingLabelWithString: "")
    super.init(nibName: nil, bundle: nil)
    title = Self.title
  }

  /// Pages of Settings are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The name of the page in the toolbar of Settings.
  static var title: String {
    String(
      localized: "Ignored Text", bundle: .module,
      comment: "Settings: the page of the ignore rules, and its toolbar item.")
  }

  override func loadView() {
    view = NSView()
    setUpTable()
    setUpButtons()
    for label in [note, reasonLabel] {
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.textColor = .secondaryLabelColor
    }
    trialField.onTextChange = { [weak self] in self?.updateTrial() }
    layOut()
    reloadRules(selecting: nil)
    // The window takes the size of the page in view from it.
    preferredContentSize = view.fittingSize
  }

  private func layOut() {
    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    let buttons = NSStackView(views: [addButton, removeButton, NSView(), duplicateButton])
    buttons.spacing = 0
    let stack = NSStackView(views: [scrollView, buttons, note, trialLabel, trialField, reasonLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = WindowMetrics.settingsSpacing
    // The buttons hang on the bottom edge of the table they act on.
    stack.setCustomSpacing(0, after: scrollView)
    stack.setCustomSpacing(WindowMetrics.settingsGroupSpacing, after: note)
    // The note and the reason keep their room while they are empty or hidden, so that nothing
    // below them moves.
    stack.detachesHiddenViews = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    let inset = WindowMetrics.settingsInset
    let contentWidth = WindowMetrics.settingsWidth - 2 * inset
    var constraints = [
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset),
      view.widthAnchor.constraint(equalToConstant: WindowMetrics.settingsWidth),
      scrollView.heightAnchor.constraint(equalToConstant: WindowMetrics.ignoreRuleTableHeight),
      trialField.heightAnchor.constraint(equalToConstant: WindowMetrics.ruleTrialHeight),
      reasonLabel.heightAnchor.constraint(
        greaterThanOrEqualToConstant: ceil(reasonLabel.font?.boundingRectForFont.height ?? 0)),
    ]
    for part in [scrollView, buttons, note, trialLabel, trialField, reasonLabel] {
      constraints.append(part.widthAnchor.constraint(equalToConstant: contentWidth))
    }
    NSLayoutConstraint.activate(constraints)
  }

  private func setUpButtons() {
    addButton.target = self
    addButton.action = #selector(addRule(_:))
    addButton.setAccessibilityLabel(
      Self.addTitle)
    addButton.toolTip = String(
      localized: "Add a rule of your own", bundle: .module,
      comment: "Help tag of the + below the ignore rules.")
    removeButton.target = self
    removeButton.action = #selector(removeRule(_:))
    removeButton.setAccessibilityLabel(Self.removeTitle)
    removeButton.toolTip = String(
      localized: "Remove the selected rule", bundle: .module,
      comment: "Help tag of the − below the ignore rules.")
    for button in [addButton, removeButton] {
      button.bezelStyle = .smallSquare
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: WindowMetrics.footerSymbolButtonWidth),
        button.heightAnchor.constraint(equalToConstant: WindowMetrics.tableButtonHeight),
      ])
    }
    // A square button like + and −, since it acts on the table as well.
    duplicateButton.bezelStyle = .smallSquare
    NSLayoutConstraint.activate([
      duplicateButton.heightAnchor.constraint(equalToConstant: WindowMetrics.tableButtonHeight),
      duplicateButton.widthAnchor.constraint(
        equalToConstant: duplicateButton.intrinsicContentSize.width + 2
          * WindowMetrics.tableButtonPadding),
    ])
    duplicateButton.target = self
    duplicateButton.action = #selector(duplicateRule(_:))
    duplicateButton.toolTip = String(
      localized: "Make a copy of the selected rule that you can change", bundle: .module,
      comment: "Help tag of Duplicate below the ignore rules.")
  }

  /// What the + and Undo call adding a rule.
  static var addTitle: String {
    String(
      localized: "Add Rule", bundle: .module,
      comment: "Settings: the + below the ignore rules for VoiceOver, and the Undo menu after it.")
  }

  /// What the −, the context menu and Undo call removing a rule.
  static var removeTitle: String {
    String(
      localized: "Remove Rule", bundle: .module,
      comment: "Settings: the − below the ignore rules for VoiceOver, the context menu and Undo.")
  }

  private static func symbol(_ name: String) -> NSImage {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
      preconditionFailure("The system has the symbol \(name)")
    }
    return image
  }

  /// What a row of the table shows.
  enum Row: Equatable {
    /// A rule that comes with the app.
    case builtIn(BuiltInIgnoreRule)

    /// The user's own rule at this index of ``UserSettings/customIgnoreRules``.
    case custom(Int)
  }

  /// What row `index` of the table shows.
  func row(at index: Int) -> Row? {
    let builtIns = BuiltInIgnoreRule.allCases
    if builtIns.indices.contains(index) { return .builtIn(builtIns[index]) }
    let custom = index - builtIns.count
    return settings.customIgnoreRules.indices.contains(custom) ? .custom(custom) : nil
  }

  /// The rule that row `index` of the table shows.
  func rule(at index: Int) -> IgnoreRule? {
    let rules = settings.ignoreRules
    return rules.indices.contains(index) ? rules[index] : nil
  }

  /// The row of the user's own rule at `index`.
  private func tableRow(ofCustomRule index: Int) -> Int {
    BuiltInIgnoreRule.allCases.count + index
  }

  /// Why the rule of row `index` leaves nothing out, as far as the page knows, or `nil`.
  func problem(ofRow index: Int) -> IgnoreRule.Problem? {
    guard var rule = rule(at: index) else { return nil }
    if index == tableView.selectedRow, let typedPattern { rule.pattern = typedPattern }
    // An empty pattern is a rule still being written, not a mistake.
    guard !rule.pattern.isEmpty else { return nil }
    return rule.problem ?? (slowPatterns.contains(rule.pattern) ? .exceedsTimeLimit : nil)
  }

  /// The rules that the settings keep, which a change replaces as a whole.
  struct Rules: Equatable {
    var builtIns: Set<BuiltInIgnoreRule>
    var custom: [IgnoreRule]
  }

  /// The rules as the settings keep them now.
  var rules: Rules {
    Rules(builtIns: settings.enabledBuiltInIgnoreRules, custom: settings.customIgnoreRules)
  }

  /// Keeps `rules` in the settings as a step of undo named `name`, and selects row `selection`
  /// of the table.
  func change(to rules: Rules, named name: String, selecting selection: Int?) {
    let previous = self.rules
    guard rules != previous else { return }
    let previousSelection = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
    settings.enabledBuiltInIgnoreRules = rules.builtIns
    settings.customIgnoreRules = rules.custom
    let undoManager = view.window?.undoManager
    undoManager?.registerUndo(withTarget: self) { page in
      MainActor.assumeIsolated {
        page.change(to: previous, named: name, selecting: previousSelection)
      }
    }
    undoManager?.setActionName(name)
    reloadRules(selecting: selection)
  }

  /// Shows the rules of the settings anew and selects row `selection`.
  func reloadRules(selecting selection: Int?) {
    typedPattern = nil
    isReloadingRules = true
    tableView.reloadData()
    isReloadingRules = false
    if let selection, selection < tableView.numberOfRows {
      tableView.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
      tableView.scrollRowToVisible(selection)
    } else {
      tableView.deselectAll(nil)
    }
    note.isHidden = !settings.customIgnoreRules.isEmpty
    selectionDidChange()
  }

  /// Fits the buttons and the trial to the selected rule.
  func selectionDidChange() {
    let selected = row(at: tableView.selectedRow)
    removeButton.isEnabled = if case .custom = selected { true } else { false }
    duplicateButton.isEnabled = selected != nil
    updateTrial()
  }

  /// Switches the rule of row `index` on or off.
  func toggleRule(atRow index: Int) {
    keepEdit()
    guard let row = row(at: index) else { return }
    var rules = rules
    switch row {
    case .builtIn(let builtIn):
      if rules.builtIns.contains(builtIn) {
        rules.builtIns.remove(builtIn)
      } else {
        rules.builtIns.insert(builtIn)
      }
    case .custom(let custom):
      rules.custom[custom].isEnabled.toggle()
    }
    change(to: rules, named: Self.changeName, selecting: index)
  }

  /// Gives the user's own rule at `index` the name `name` or the pattern `pattern`.
  func edit(customRule index: Int, name: String? = nil, pattern: String? = nil) {
    var rules = rules
    guard rules.custom.indices.contains(index) else { return }
    if let name { rules.custom[index].name = name }
    if let pattern { rules.custom[index].pattern = pattern }
    change(to: rules, named: Self.changeName, selecting: tableView.selectedRow)
  }

  /// Adds an own rule, switched on, and starts to edit its name.
  @objc func addRule(_ sender: Any?) {
    keepEdit()
    var rules = rules
    rules.custom.append(IgnoreRule(name: "", pattern: ""))
    let row = tableRow(ofCustomRule: rules.custom.count - 1)
    change(to: rules, named: Self.addTitle, selecting: row)
    editName(ofRow: row)
  }

  /// Removes the selected own rule and selects the one after it, or else the one before.
  @objc func removeRule(_ sender: Any?) {
    keepEdit()
    guard case .custom(let index) = row(at: tableView.selectedRow) else { return }
    var rules = rules
    rules.custom.remove(at: index)
    let selection =
      rules.custom.isEmpty ? nil : tableRow(ofCustomRule: min(index, rules.custom.count - 1))
    change(to: rules, named: Self.removeTitle, selecting: selection)
  }

  /// Adds an own copy of the selected rule after the user's other rules, and starts to edit
  /// its name.
  @objc func duplicateRule(_ sender: Any?) {
    keepEdit()
    guard let original = rule(at: tableView.selectedRow) else { return }
    var rules = rules
    var copy = original
    copy.name = IgnoreRule.nameOfCopy(of: original.name)
    rules.custom.append(copy)
    let row = tableRow(ofCustomRule: rules.custom.count - 1)
    change(
      to: rules,
      named: String(
        localized: "Duplicate Rule", bundle: .module, comment: "Undo menu: a rule was copied."),
      selecting: row)
    editName(ofRow: row)
  }

  /// Keeps what is typed into a name or a pattern before another change, since the buttons
  /// take no focus and the edit would go on.
  private func keepEdit() {
    guard tableView.editedRow >= 0 || view.window?.firstResponder is NSText else { return }
    view.window?.makeFirstResponder(tableView)
  }

  /// Puts the insertion point into the name of row `row`, if it can be changed.
  func editName(ofRow row: Int) {
    guard case .custom = self.row(at: row),
      let column = tableView.tableColumns.firstIndex(where: {
        $0.identifier == Column.name.identifier
      })
    else { return }
    tableView.editColumn(column, row: row, with: nil, select: true)
  }

  /// What Undo calls a change of a rule: its name, its pattern, or whether it is on.
  private static var changeName: String {
    String(
      localized: "Change Rule", bundle: .module,
      comment: "Undo menu: an ignore rule was renamed, got another pattern, or was switched.")
  }

  /// Takes `pattern`, typed into the field of the selected rule, for the trial and the warning
  /// of its row before it is kept.
  func patternIsBeingTyped(_ pattern: String?) {
    typedPattern = pattern
    updateTrial()
  }

  /// Tries the selected rule on the text of the field and marks what it leaves out, or says why
  /// it leaves out nothing.
  func updateTrial() {
    trialTask?.cancel()
    trialTask = nil
    let selectedRow = tableView.selectedRow
    guard var rule = rule(at: selectedRow) else {
      show(.matches([]), forRow: selectedRow)
      return
    }
    if let typedPattern { rule.pattern = typedPattern }
    if let problem = problem(ofRow: selectedRow) {
      show(.problem(problem), forRow: selectedRow)
      return
    }
    let text = trialField.text
    guard !text.isEmpty, !rule.pattern.isEmpty else {
      show(.matches([]), forRow: selectedRow)
      return
    }
    let mode = settings.comparisonMode
    trialTask = Task { [weak self] in
      let trial = await rule.trial(on: text, mode: mode)
      guard !Task.isCancelled, let self else { return }
      if trial == .problem(.exceedsTimeLimit) {
        self.slowPatterns.insert(rule.pattern)
        self.reloadWarning(ofRow: selectedRow)
      }
      self.show(trial, forRow: selectedRow)
    }
  }

  private func show(_ trial: IgnoreRule.Trial, forRow row: Int) {
    switch trial {
    case .matches(let ranges):
      trialField.mark(ranges)
      reasonLabel.stringValue = ""
    case .problem(let problem):
      trialField.mark([])
      reasonLabel.stringValue = problem.reason
    }
  }
}
