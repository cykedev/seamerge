import AppKit
import MergeModel

/// The toolbar of a session window: in the middle the number of open conflicts with the arrows
/// that jump between them, at the trailing end the choice of how the lines are laid out and the
/// button that saves and closes.
///
/// A comparison of two files has no conflicts and nothing to save: in the middle it says which
/// change is current, with the arrows that jump between changes, and at the trailing end the
/// choice of how the lines are laid out, which offers a single column besides. How the files
/// are compared stands in the footer of the window.
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

  /// The arrangements that the choice in the toolbar offers, in its order.
  let arrangements: [LineArrangement]
  private let hasSidebar: Bool
  private let countLabel = NSTextField(labelWithString: "")
  private let progressIndicator = NSProgressIndicator()
  private let countView: NSStackView
  private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

  /// Creates the toolbar of a window of `kind`, with the button that saves and closes in
  /// `doneStyle` if it has one.
  init(kind: Session.Kind, doneStyle: DoneStyle, hasSidebar: Bool = false) {
    self.kind = kind
    self.doneStyle = doneStyle
    arrangements = LineArrangement.choices(inMerge: kind == .merge)
    self.hasSidebar = hasSidebar
    toolbar = NSToolbar(
      identifier: kind == .merge
        ? "SessionToolbar" : hasSidebar ? "CollectionToolbar" : "ComparisonToolbar")
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

  /// Shows the state of the window: the count in the middle, which arrows lead anywhere and
  /// whether the button that saves and closes can act, whether a comparison is under way, and
  /// whether that button is the one to press.
  ///
  /// - Parameters:
  ///   - count: The conflicts or changes to count.
  ///   - isComparing: Whether the files are being compared anew for long enough to say so.
  ///   - lineArrangement: How the lines are laid out now.
  ///   - canShow: Whether the lines can be laid out in an arrangement now.
  ///   - isValid: Whether a command can act now.
  func update(
    count: Count, isComparing: Bool, lineArrangement: LineArrangement,
    canShow: (LineArrangement) -> Bool, isValid: (SessionCommand) -> Bool
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
    if let group = items[.lineArrangement] as? NSToolbarItemGroup {
      group.selectedIndex = arrangements.firstIndex(of: lineArrangement) ?? -1
      for (subitem, arrangement) in zip(group.subitems, arrangements) {
        subitem.isEnabled = canShow(arrangement)
      }
    }
    if let done = items[.done] {
      done.isEnabled = isValid(.saveAndClose)
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
      item.label = SessionCommand.comparisonModeLabel
      item.image = NSImage(
        systemSymbolName: "equal.square", accessibilityDescription: item.label)
      item.paletteLabel = item.label
      item.toolTip = SessionCommand.comparisonModeHelp
      item.menu = Self.menu(of: SessionCommand.groups(in: .compare))
      return item
    case .lineArrangement:
      return arrangementGroup()
    case .done:
      let item = NSToolbarItem(itemIdentifier: identifier)
      let title = String(
        localized: "Done", bundle: .module, comment: "Toolbar button: save and close.")
      // VoiceOver says what the button does in the words of the menu, since the find bar has a
      // Done of its own that only closes the bar.
      let label = SessionCommand.saveAndClose.title
      switch doneStyle {
      case .checkmark:
        item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: label)
      case .word:
        item.title = title
      }
      item.label = label
      item.paletteLabel = label
      item.toolTip = SessionCommand.saveAndClose.help
      item.action = SessionCommand.saveAndClose.action
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

  /// The choice of how the lines are laid out: one segment for each arrangement, with its
  /// symbol, of which the one in effect is selected.
  ///
  /// A click sends ``SessionWindowController/chooseLineArrangement(_:)`` with the group, whose
  /// selected segment names the arrangement; the View menu offers the same arrangements in the
  /// same words.
  private func arrangementGroup() -> NSToolbarItemGroup {
    let group = NSToolbarItemGroup(
      itemIdentifier: .lineArrangement,
      images: arrangements.map { arrangement in
        NSImage(
          systemSymbolName: arrangement.symbolName, accessibilityDescription: arrangement.title)
          ?? NSImage()
      },
      selectionMode: .selectOne, labels: arrangements.map(\.title), target: nil,
      action: #selector(SessionWindowController.chooseLineArrangement(_:)))
    for (subitem, arrangement) in zip(group.subitems, arrangements) {
      subitem.toolTip = arrangement.help
      subitem.autovalidates = false
    }
    group.label = Self.arrangementLabel
    group.paletteLabel = Self.arrangementLabel
    group.autovalidates = false
    return group
  }

  /// The label of the choice of how the lines are laid out.
  static var arrangementLabel: String {
    String(
      localized: "Arrangement", bundle: .module,
      comment: "Toolbar item: the choice of how the lines of the files are laid out.")
  }

  /// The arrangement whose segment is selected in `group`, the choice of the toolbar, if any.
  func arrangement(chosenIn group: NSToolbarItemGroup) -> LineArrangement? {
    arrangements.indices.contains(group.selectedIndex) ? arrangements[group.selectedIndex] : nil
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

  /// The elements of a merge: the conflicts in the middle and Done at the end; those of a
  /// comparison: the changes in the middle.
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    let sidebarItems: [NSToolbarItem.Identifier] =
      hasSidebar ? [.toggleSidebar, .sidebarTrackingSeparator] : []
    return switch kind {
    case .merge: [.conflictCount, .conflictNavigation, .flexibleSpace, .lineArrangement, .done]
    case .diff: sidebarItems + [.changeCount, .changeNavigation, .flexibleSpace, .lineArrangement]
    }
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    switch kind {
    case .merge:
      [
        .conflictCount, .conflictNavigation, .changeNavigation, .lineArrangement, .comparison,
        .done, .flexibleSpace, .space,
      ]
    case .diff:
      (hasSidebar ? [.toggleSidebar, .sidebarTrackingSeparator] : [])
        + [.changeCount, .changeNavigation, .lineArrangement, .comparison, .flexibleSpace, .space]
    }
  }

  /// Adds the choice of the arrangement to the toolbar once, if a configuration that the user
  /// saved before the choice existed leaves it out, before the button that saves and closes or at
  /// the end; the rest of the configuration stays.
  ///
  /// Each kind of toolbar does so once, as `settings` remember, so that a user who removes the
  /// choice later does not get it back.
  func insertArrangementOnce(rememberingIn settings: UserSettings) {
    let identifier = toolbar.identifier
    guard !settings.toolbarsWithArrangement.contains(identifier) else { return }
    settings.toolbarsWithArrangement.insert(identifier)
    let identifiers = toolbar.items.map(\.itemIdentifier)
    guard !identifiers.contains(.lineArrangement) else { return }
    toolbar.insertItem(
      withItemIdentifier: .lineArrangement,
      at: identifiers.firstIndex(of: .done) ?? identifiers.count)
  }

  /// Shows the button that shows and hides the sidebar, or hides it while the window has too
  /// few files for a list.
  func showsSidebarButton(_ shows: Bool) {
    for item in toolbar.items where item.itemIdentifier == .toggleSidebar {
      item.isHidden = !shows
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
  static let lineArrangement = Self("lineArrangement")
  static let done = Self("done")
}
