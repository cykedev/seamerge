import AppKit
import MergeModel

/// The toolbar of a session window: in the middle the number of open conflicts with the arrows
/// that jump between them, at the trailing end a menu of the comparison and view options and
/// the button that saves and closes.
///
/// A comparison of two files has no conflicts and nothing to save: in the middle it says which
/// change is current, with the arrows that jump between changes, and at the trailing end it has
/// only the menu of options.
///
/// The toolbar can be customized, for each kind of window on its own; in a merge, the arrows
/// between changes can be dragged in, and in both the choice of the comparison mode, but they
/// are not there by default. Every item sends the action of a
/// command of the window, which the main menu offers as well. The toolbar does not validate its
/// items itself: the window tells it when they change.
@MainActor
final class SessionToolbar: NSObject {
  /// How the button that saves and closes shows itself.
  enum DoneStyle {
    /// A checkmark.
    case checkmark

    /// The word Done.
    case word

    /// How a window shows the button.
    static let standard = DoneStyle.word
  }

  /// What the toolbar counts in its middle.
  enum Count: Equatable {
    /// The conflicts of a merge: how many are open, and whether the merge had any.
    case conflicts(open: Int, hadAny: Bool)

    /// The changes of a comparison: the index of the current one, if any, and how many there
    /// are.
    case changes(current: Int?, total: Int)

    /// Nothing, for a comparison whose files cannot be compared.
    case nothing
  }

  /// The toolbar of the window.
  let toolbar: NSToolbar

  private let kind: Session.Kind
  private let doneStyle: DoneStyle
  private let countLabel = NSTextField(labelWithString: "")
  private let progressIndicator = NSProgressIndicator()
  private let countView: NSStackView
  private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

  /// Creates the toolbar of a window of `kind`, with the button that saves and closes in
  /// `doneStyle` if it has one.
  init(kind: Session.Kind, doneStyle: DoneStyle) {
    self.kind = kind
    self.doneStyle = doneStyle
    toolbar = NSToolbar(identifier: kind == .merge ? "SessionToolbar" : "ComparisonToolbar")
    progressIndicator.style = .spinning
    progressIndicator.controlSize = .small
    progressIndicator.isDisplayedWhenStopped = false
    countLabel.font = .preferredFont(forTextStyle: .headline)
    countLabel.textColor = .labelColor
    countView = NSStackView(views: [progressIndicator, countLabel])
    countView.spacing = WindowMetrics.headerSpacing
    super.init()
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = true
    toolbar.autosavesConfiguration = true
    toolbar.centeredItemIdentifiers =
      kind == .merge ? [.conflictCount, .conflictNavigation] : [.changeCount, .changeNavigation]
  }

  /// The left edge of the count in the middle in the coordinates of the window, once the
  /// toolbar has laid it out.
  var countMinX: CGFloat? {
    guard countView.window != nil, countView.frame.width > 0 else { return nil }
    return countView.convert(countView.bounds, to: nil).minX
  }

  /// Shows the state of the window: the count in the middle, which arrows lead anywhere,
  /// whether a comparison is under way, and whether the button that saves and closes can act
  /// and is the one to press.
  ///
  /// - Parameters:
  ///   - count: The conflicts or changes to count.
  ///   - isComparing: Whether the files are being compared anew for long enough to say so.
  ///   - isValid: Whether a command can act now.
  ///   - canSaveAndClose: Whether a responder saves and closes.
  func update(
    count: Count, isComparing: Bool, isValid: (SessionCommand) -> Bool, canSaveAndClose: Bool
  ) {
    countLabel.stringValue =
      isComparing
      ? String(
        localized: "Comparing…", bundle: .module,
        comment: "Toolbar: the files are being compared anew.")
      : Self.countText(count)
    countView.setAccessibilityLabel(countLabel.stringValue)
    if isComparing {
      progressIndicator.startAnimation(nil)
    } else {
      progressIndicator.stopAnimation(nil)
    }
    switch count {
    case .conflicts(let open, _): items[.conflictNavigation]?.isHidden = open == 0
    case .changes(_, let total): items[.changeNavigation]?.isHidden = total == 0
    case .nothing: items[.changeNavigation]?.isHidden = true
    }
    for item in [items[.conflictNavigation], items[.changeNavigation]] {
      for subitem in (item as? NSToolbarItemGroup)?.subitems ?? [] {
        subitem.isEnabled = SessionCommand(action: subitem.action).map(isValid) ?? false
      }
    }
    if let done = items[.done] {
      done.isEnabled = canSaveAndClose
      let isResolved = if case .conflicts(open: 0, _) = count { true } else { false }
      done.style = isResolved ? .prominent : .plain
    }
  }

  /// What the toolbar says in its middle.
  static func countText(_ count: Count) -> String {
    switch count {
    case .conflicts(let open, let hadAny):
      countText(openConflictCount: open, hasConflicts: hadAny)
    case .changes(let current, let total):
      countText(currentChange: current, changeCount: total)
    case .nothing:
      ""
    }
  }

  /// What the toolbar of a comparison says about the changes: which one is current, counted
  /// from 1, or how many there are while none is.
  static func countText(currentChange: Int?, changeCount: Int) -> String {
    guard changeCount > 0 else {
      return String(
        localized: "No Changes", bundle: .module,
        comment: "Toolbar: the two files are equal under the comparison mode.")
    }
    guard let currentChange else {
      return String(
        localized: "\(changeCount) Changes", bundle: .module,
        comment: "Toolbar: the changes of a comparison while none is current, such as 12 Changes.")
    }
    return String(
      localized: "Change \(currentChange + 1) of \(changeCount)", bundle: .module,
      comment: "Toolbar: the current change of a comparison, such as Change 4 of 12.")
  }

  /// What the toolbar says about the conflicts.
  static func countText(openConflictCount: Int, hasConflicts: Bool) -> String {
    if openConflictCount > 0 {
      return String(
        localized: "\(openConflictCount) Conflicts Left", bundle: .module,
        comment: "Toolbar: how many conflicts are still open, such as 2 Conflicts Left.")
    }
    return hasConflicts
      ? String(
        localized: "All Conflicts Resolved", bundle: .module,
        comment: "Toolbar: every conflict is resolved.")
      : String(
        localized: "No Conflicts", bundle: .module, comment: "Toolbar: the merge had no conflict.")
  }

  /// The label of the count of the open conflicts and of the buttons that go through them.
  ///
  /// Both items take one string, so that the string catalog keeps one comment for it.
  private static var conflictsLabel: String {
    String(
      localized: "Conflicts", bundle: .module,
      comment:
        "Toolbar items: the count of the open conflicts and the buttons that go through them.")
  }

  /// The label of the place of the current change and of the buttons that go through the changes.
  private static var changesLabel: String {
    String(
      localized: "Changes", bundle: .module,
      comment: "Toolbar items: the current change and the buttons that go through the changes.")
  }

  /// The action that the button that saves and closes sends along the responder chain.
  static let saveAndClose = Selector(("saveAndClose:"))

  private func makeItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
    switch identifier {
    case .conflictCount:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.view = countView
      item.isBordered = false
      item.label = Self.conflictsLabel
      item.paletteLabel = item.label
      return item
    case .changeCount:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.view = countView
      item.isBordered = false
      item.label = Self.changesLabel
      item.paletteLabel = item.label
      return item
    case .conflictNavigation:
      return group(
        identifier, label: Self.conflictsLabel,
        paletteLabel: String(
          localized: "Previous and Next Conflict", bundle: .module,
          comment: "Toolbar item in the customization sheet."),
        commands: [.previousConflict, .nextConflict])
    case .changeNavigation:
      return group(
        identifier, label: Self.changesLabel,
        paletteLabel: String(
          localized: "Previous and Next Change", bundle: .module,
          comment: "Toolbar item in the customization sheet."),
        commands: [.previousChange, .nextChange])
    case .comparison:
      let item = NSMenuToolbarItem(itemIdentifier: identifier)
      item.label = String(
        localized: "Comparison", bundle: .module, comment: "Toolbar item: the comparison mode.")
      item.image = NSImage(
        systemSymbolName: "equal.square", accessibilityDescription: item.label)
      item.paletteLabel = item.label
      item.toolTip = String(
        localized: "Choose how lines are compared", bundle: .module,
        comment: "Help tag of the comparison item in the toolbar.")
      item.menu = Self.menu(of: SessionCommand.groups(in: .compare))
      return item
    case .options:
      let item = NSMenuToolbarItem(itemIdentifier: identifier)
      item.label = String(
        localized: "Options", bundle: .module, comment: "Toolbar item: comparison and view options."
      )
      item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: item.label)
      item.showsIndicator = false
      item.paletteLabel = item.label
      item.toolTip = String(
        localized: "Change how the files are compared and shown", bundle: .module,
        comment: "Help tag of the options item in the toolbar.")
      item.menu = Self.menu(of: SessionCommand.optionsGroups(in: kind))
      return item
    case .done:
      let item = NSToolbarItem(itemIdentifier: identifier)
      let title = String(
        localized: "Done", bundle: .module, comment: "Toolbar button: save and close.")
      switch doneStyle {
      case .checkmark:
        item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: title)
      case .word:
        item.title = title
      }
      item.label = title
      item.paletteLabel = title
      item.toolTip = String(
        localized: "Save and close", bundle: .module, comment: "Help tag of Done in the toolbar.")
      item.action = Self.saveAndClose
      item.autovalidates = false
      item.isEnabled = false
      return item
    default:
      return nil
    }
  }

  /// A pair of arrows that send `commands`, the one going up and the one going down.
  private func group(
    _ identifier: NSToolbarItem.Identifier, label: String, paletteLabel: String,
    commands: [SessionCommand]
  ) -> NSToolbarItemGroup {
    let symbols = ["chevron.up", "chevron.down"]
    let subitems = zip(commands, symbols).enumerated().map { index, pair in
      let (command, symbol) = pair
      let item = NSToolbarItem(
        itemIdentifier: NSToolbarItem.Identifier("\(identifier.rawValue).\(index)"))
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: command.title)
      item.label = command.title
      item.toolTip = command.help
      item.action = command.action
      item.autovalidates = false
      return item
    }
    let group = NSToolbarItemGroup(itemIdentifier: identifier)
    group.subitems = subitems
    group.label = label
    group.paletteLabel = paletteLabel
    group.autovalidates = false
    return group
  }

  /// A menu of `groups` of commands, with a separator between groups.
  private static func menu(of groups: [[SessionCommand]]) -> NSMenu {
    let menu = NSMenu()
    for (index, group) in groups.enumerated() {
      if index > 0 {
        menu.addItem(.separator())
      }
      for command in group {
        let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
        item.toolTip = command.help
        menu.addItem(item)
      }
    }
    return menu
  }
}

extension SessionToolbar: NSToolbarDelegate {
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    let item = makeItem(itemIdentifier)
    if flag {
      items[itemIdentifier] = item
    }
    return item
  }

  /// The three elements of a merge: the conflicts in the middle, the options and Done at the
  /// end, the two apart, since the toolbar would join a checkmark and the options into one group;
  /// the two of a comparison: the changes in the middle, the options at the end.
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    switch (kind, doneStyle) {
    case (.merge, .word): [.conflictCount, .conflictNavigation, .flexibleSpace, .options, .done]
    case (.merge, .checkmark):
      [.conflictCount, .conflictNavigation, .flexibleSpace, .options, .space, .done]
    case (.diff, _): [.changeCount, .changeNavigation, .flexibleSpace, .options]
    }
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    switch kind {
    case .merge:
      [
        .conflictCount, .conflictNavigation, .changeNavigation, .comparison, .options, .done,
        .flexibleSpace, .space,
      ]
    case .diff: [.changeCount, .changeNavigation, .comparison, .options, .flexibleSpace, .space]
    }
  }

  func toolbarDidRemoveItem(_ notification: Notification) {
    guard let item = notification.userInfo?["item"] as? NSToolbarItem else { return }
    items[item.itemIdentifier] = nil
  }
}

extension NSToolbarItem.Identifier {
  static let conflictCount = Self("conflictCount")
  static let changeCount = Self("changeCount")
  static let conflictNavigation = Self("conflictNavigation")
  static let changeNavigation = Self("changeNavigation")
  static let comparison = Self("comparison")
  static let options = Self("options")
  static let done = Self("done")
}
