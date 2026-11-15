import AppKit
import MergeModel

extension IgnoredTextViewController: NSTableViewDataSource, NSTableViewDelegate,
  NSTextFieldDelegate, NSMenuDelegate
{
  /// Sets up the table: a switch, the name and the pattern of each rule, one rule selected at a
  /// time, the keys of the table and its context menu.
  func setUpTable() {
    let titles: [Column: String] = [
      .isEnabled: "",
      .name: IgnoreRule.namePlaceholder,
      .pattern: String(
        localized: "Pattern", bundle: .module, comment: "Settings: the column of the patterns."),
    ]
    for column in Column.allCases {
      let tableColumn = NSTableColumn(identifier: column.identifier)
      tableColumn.title = titles[column] ?? ""
      switch column {
      case .isEnabled:
        tableColumn.width = WindowMetrics.ignoreRuleSwitchColumnWidth
        tableColumn.resizingMask = []
      case .name:
        tableColumn.width = WindowMetrics.ignoreRuleNameColumnWidth
        tableColumn.resizingMask = .userResizingMask
      case .pattern:
        tableColumn.resizingMask = .autoresizingMask
      }
      tableView.addTableColumn(tableColumn)
    }
    tableView.style = .fullWidth
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.allowsMultipleSelection = false
    tableView.allowsColumnReordering = false
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.dataSource = self
    tableView.delegate = self
    tableView.setAccessibilityLabel(
      String(
        localized: "Ignore Rules", bundle: .module,
        comment: "VoiceOver: the table of the ignore rules in Settings."))
    tableView.perform = { [weak self] command in self?.perform(command) ?? false }
    let menu = NSMenu()
    menu.delegate = self
    tableView.menu = menu
  }

  /// Carries out a key command of the table on the selected rule; tells whether it had an
  /// effect.
  private func perform(_ command: IgnoreRuleTableView.KeyCommand) -> Bool {
    let selected = tableView.selectedRow
    guard let row = row(at: selected) else { return false }
    switch command {
    case .toggle:
      toggleRule(atRow: selected)
      return true
    case .edit:
      guard case .custom = row else { return false }
      editName(ofRow: selected)
      return true
    case .remove:
      guard case .custom = row else { return false }
      removeRule(nil)
      return true
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    settings.ignoreRules.count
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int
  ) -> NSView? {
    guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
      let row = row(at: index), let rule = rule(at: index)
    else { return nil }
    let isBuiltIn = if case .builtIn = row { true } else { false }
    switch column {
    case .isEnabled:
      let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
      toggle.state = rule.isEnabled ? .on : .off
      toggle.setAccessibilityLabel(rule.name.isEmpty ? IgnoreRule.namePlaceholder : rule.name)
      return centered(toggle)
    case .name:
      let field = cellField(text: rule.name, isEditable: !isBuiltIn)
      field.placeholderString = IgnoreRule.namePlaceholder
      field.setAccessibilityLabel(titleOfColumn(.name))
      if isBuiltIn { field.toolTip = Self.builtInHelp }
      return textCell(field, accessory: nil)
    case .pattern:
      return patternCell(of: rule, row: index, isBuiltIn: isBuiltIn)
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    selectionDidChange()
  }

  /// The help tag of the name and pattern of a rule that comes with the app.
  private static var builtInHelp: String {
    String(
      localized: "Duplicate this rule to change it", bundle: .module,
      comment: "Help tag of the name and pattern of an ignore rule that comes with the app.")
  }

  private func titleOfColumn(_ column: Column) -> String {
    tableView.tableColumn(withIdentifier: column.identifier)?.title ?? ""
  }

  /// A text field for a cell of the table, which can be edited if `isEditable`.
  private func cellField(text: String, isEditable: Bool) -> NSTextField {
    let field = NSTextField(string: text)
    field.isBordered = false
    field.drawsBackground = false
    field.isEditable = isEditable
    field.isSelectable = isEditable
    field.lineBreakMode = .byTruncatingTail
    field.cell?.truncatesLastVisibleLine = true
    field.textColor = isEditable ? .labelColor : .secondaryLabelColor
    field.delegate = self
    return field
  }

  /// The cell of the pattern of `rule` in row `row`: the pattern in the font of code, and the
  /// warning with its reason if the rule leaves nothing out.
  private func patternCell(of rule: IgnoreRule, row: Int, isBuiltIn: Bool) -> NSView {
    let field = cellField(text: rule.pattern, isEditable: !isBuiltIn)
    field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.placeholderString = IgnoreRule.patternPlaceholder
    field.setAccessibilityLabel(titleOfColumn(.pattern))
    if isBuiltIn { field.toolTip = Self.builtInHelp }
    let warning = NSImageView()
    showWarning(problem(ofRow: row), in: warning)
    return textCell(field, accessory: warning)
  }

  /// A cell with `field` and `accessory` after it: the text stands on the same baseline in
  /// every column, whatever its font, in the middle of the row.
  private func textCell(_ field: NSTextField, accessory: NSView?) -> NSView {
    let cell = NSView()
    let parts = [field] + (accessory.map { [$0] } ?? [])
    for part in parts {
      part.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(part)
    }
    let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    var constraints = [
      field.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
      field.firstBaselineAnchor.constraint(
        equalTo: cell.centerYAnchor, constant: (systemFont.capHeight / 2).rounded()),
    ]
    if let accessory {
      accessory.setContentHuggingPriority(.required, for: .horizontal)
      accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
      constraints += [
        accessory.leadingAnchor.constraint(
          equalTo: field.trailingAnchor, constant: WindowMetrics.ignoreRuleCellSpacing),
        accessory.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
        accessory.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ]
    } else {
      constraints.append(field.trailingAnchor.constraint(equalTo: cell.trailingAnchor))
    }
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    NSLayoutConstraint.activate(constraints)
    return cell
  }

  /// Shows the warning of `problem` in `warning`, or hides it.
  private func showWarning(_ problem: IgnoreRule.Problem?, in warning: NSImageView) {
    warning.isHidden = problem == nil
    warning.image = problem.flatMap {
      NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: $0.reason)
    }
    warning.toolTip = problem?.reason
  }

  /// Shows anew whether the rule of row `row` warns, as after a trial found it too slow or
  /// while its pattern is typed.
  func reloadWarning(ofRow row: Int) {
    guard
      let column = tableView.tableColumns.firstIndex(where: {
        $0.identifier == Column.pattern.identifier
      }),
      let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false),
      let warning = cell.subviews.compactMap({ $0 as? NSImageView }).first
    else { return }
    showWarning(problem(ofRow: row), in: warning)
  }

  /// `view` in the middle of a cell.
  private func centered(_ view: NSView) -> NSView {
    let cell = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(view)
    NSLayoutConstraint.activate([
      view.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
      view.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  @objc private func toggle(_ sender: NSButton) {
    let row = tableView.row(for: sender)
    guard row >= 0 else { return }
    toggleRule(atRow: row)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, isPatternField(field) else { return }
    let row = tableView.row(for: field)
    guard row == tableView.selectedRow else { return }
    patternIsBeingTyped(field.stringValue)
    reloadWarning(ofRow: row)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard !isReloadingRules, let field = notification.object as? NSTextField else { return }
    let row = tableView.row(for: field)
    guard case .custom(let index) = self.row(at: row) else { return }
    if isPatternField(field) {
      patternIsBeingTyped(nil)
      edit(customRule: index, pattern: field.stringValue)
      reloadWarning(ofRow: row)
    } else {
      edit(customRule: index, name: field.stringValue)
    }
  }

  /// Moves from the name to the pattern with Tab and back with Shift-Tab, as from one field of a
  /// form to the next.
  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    guard let field = control as? NSTextField else { return false }
    let row = tableView.row(for: field)
    let target: Column
    switch commandSelector {
    case #selector(NSResponder.insertTab(_:)) where !isPatternField(field): target = .pattern
    case #selector(NSResponder.insertBacktab(_:)) where isPatternField(field): target = .name
    default: return false
    }
    guard
      let column = tableView.tableColumns.firstIndex(where: { $0.identifier == target.identifier })
    else { return false }
    view.window?.makeFirstResponder(tableView)
    tableView.editColumn(column, row: row, with: nil, select: true)
    return true
  }

  private func isPatternField(_ field: NSTextField) -> Bool {
    let column = tableView.column(for: field)
    return column >= 0 && tableView.tableColumns[column].identifier == Column.pattern.identifier
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    fillContextMenu(menu, forRow: tableView.clickedRow)
  }

  /// Fills `menu` with what can be done to the rule of row `clicked`, which it selects.
  func fillContextMenu(_ menu: NSMenu, forRow clicked: Int) {
    menu.removeAllItems()
    guard let row = row(at: clicked) else { return }
    tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
    menu.addItem(
      withTitle: duplicateButton.title, action: #selector(duplicateRule(_:)), keyEquivalent: ""
    ).target = self
    if case .custom = row {
      menu.addItem(
        withTitle: Self.removeTitle, action: #selector(removeRule(_:)), keyEquivalent: ""
      )
      .target = self
    }
  }
}
