import AppKit
import MergeModel

/// The toolbar of a session window: in the middle the number of open conflicts with the arrows
/// that jump between them, at the trailing end a menu of the comparison and view options and
/// the button that saves and closes.
///
/// The toolbar can be customized; the arrows between changes and the choice of the comparison
/// mode can be dragged in, but are not there by default. Every item sends the action of a
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

  /// The toolbar of the window.
  let toolbar = NSToolbar(identifier: "SessionToolbar")

  private let doneStyle: DoneStyle
  private let countLabel = NSTextField(labelWithString: "")
  private let progressIndicator = NSProgressIndicator()
  private let countView: NSStackView
  private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

  /// Creates the toolbar, with the button that saves and closes in `doneStyle`.
  init(doneStyle: DoneStyle) {
    self.doneStyle = doneStyle
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
    toolbar.centeredItemIdentifiers = [.conflictCount, .conflictNavigation]
  }

  /// The left edge of the number of open conflicts in the coordinates of the window, once the
  /// toolbar has laid it out.
  var conflictCountMinX: CGFloat? {
    guard countView.window != nil, countView.frame.width > 0 else { return nil }
    return countView.convert(countView.bounds, to: nil).minX
  }

  /// Shows the state of the window: the number of open conflicts, which arrows lead anywhere,
  /// whether a comparison is under way, and whether the button that saves and closes can act
  /// and is the one to press.
  ///
  /// - Parameters:
  ///   - openConflictCount: The conflicts still open.
  ///   - hasConflicts: Whether the merge had any conflict at all.
  ///   - isComparing: Whether the files are being compared anew for long enough to say so.
  ///   - isValid: Whether a command can act now.
  ///   - canSaveAndClose: Whether a responder saves and closes.
  func update(
    openConflictCount: Int, hasConflicts: Bool, isComparing: Bool,
    isValid: (SessionCommand) -> Bool, canSaveAndClose: Bool
  ) {
    let count = Self.countText(openConflictCount: openConflictCount, hasConflicts: hasConflicts)
    countLabel.stringValue =
      isComparing
      ? String(
        localized: "Comparing…", bundle: .module,
        comment: "Toolbar: the files are being compared anew.")
      : count
    countView.setAccessibilityLabel(countLabel.stringValue)
    if isComparing {
      progressIndicator.startAnimation(nil)
    } else {
      progressIndicator.stopAnimation(nil)
    }
    items[.conflictNavigation]?.isHidden = openConflictCount == 0
    for item in [items[.conflictNavigation], items[.changeNavigation]] {
      for subitem in (item as? NSToolbarItemGroup)?.subitems ?? [] {
        subitem.isEnabled = SessionCommand(action: subitem.action).map(isValid) ?? false
      }
    }
    if let done = items[.done] {
      done.isEnabled = canSaveAndClose
      done.style = openConflictCount == 0 ? .prominent : .plain
    }
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

  /// The action that the button that saves and closes sends along the responder chain.
  static let saveAndClose = Selector(("saveAndClose:"))

  private func makeItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
    switch identifier {
    case .conflictCount:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.view = countView
      item.isBordered = false
      item.label = String(
        localized: "Conflicts", bundle: .module, comment: "Toolbar item: the open conflicts.")
      item.paletteLabel = item.label
      return item
    case .conflictNavigation:
      return group(
        identifier, label: String(localized: "Conflicts", bundle: .module, comment: "Toolbar."),
        paletteLabel: String(
          localized: "Previous and Next Conflict", bundle: .module,
          comment: "Toolbar item in the customization sheet."),
        commands: [.previousConflict, .nextConflict])
    case .changeNavigation:
      return group(
        identifier, label: String(localized: "Changes", bundle: .module, comment: "Toolbar."),
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
      item.menu = Self.menu(of: SessionCommand.optionsGroups)
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

  /// The three elements: the conflicts in the middle, the options and Done at the end, the
  /// two apart, since the toolbar would join a checkmark and the options into one group.
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    switch doneStyle {
    case .word: [.conflictCount, .conflictNavigation, .flexibleSpace, .options, .done]
    case .checkmark: [.conflictCount, .conflictNavigation, .flexibleSpace, .options, .space, .done]
    }
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .conflictCount, .conflictNavigation, .changeNavigation, .comparison, .options, .done,
      .flexibleSpace, .space,
    ]
  }

  func toolbarDidRemoveItem(_ notification: Notification) {
    guard let item = notification.userInfo?["item"] as? NSToolbarItem else { return }
    items[item.itemIdentifier] = nil
  }
}

extension NSToolbarItem.Identifier {
  static let conflictCount = Self("conflictCount")
  static let conflictNavigation = Self("conflictNavigation")
  static let changeNavigation = Self("changeNavigation")
  static let comparison = Self("comparison")
  static let options = Self("options")
  static let done = Self("done")
}
