import AppKit
import MergeModel

/// The keyboard shortcuts of a kind of window, gathered by the menu that holds their commands:
/// what the overview of the shortcuts lists.
struct ShortcutOverview {
  /// A command with its shortcut and the single key that does the same in block mode.
  struct Entry: Hashable, Identifiable {
    /// The command.
    let command: SessionCommand

    /// The shortcut as the menu shows it, such as “⌥⌘↓”, or `nil` for a command without one.
    let shortcut: String?

    /// The keys that do the same without Command while the result does not take typing, such as
    /// “1 or ←”, or `nil` for a command without any.
    let singleKeys: String?

    var id: SessionCommand { command }

    /// What VoiceOver says for the entry: the title, the shortcut, and the single keys.
    var spokenDescription: String {
      switch (shortcut, singleKeys) {
      case (let shortcut?, let singleKeys?):
        String(
          localized: "\(title), \(shortcut), or \(singleKeys)", bundle: .module,
          comment: "VoiceOver, Keyboard Shortcuts: a command, its shortcut and its single keys.")
      case (let keys?, nil), (nil, let keys?):
        String(
          localized: "\(title), \(keys)", bundle: .module,
          comment: "VoiceOver, Keyboard Shortcuts: a command and its shortcut or single keys.")
      case (nil, nil):
        title
      }
    }

    /// The name of the command: as its menu item shows it while the window starts, and with
    /// the name of its submenu where the item alone would only name a side.
    var title: String {
      command.submenuTitle == nil ? command.title : command.undoName ?? command.title
    }
  }

  /// The commands of one menu that have a shortcut or a single key.
  struct Group: Hashable, Identifiable {
    /// The menu that holds the commands.
    let menu: SessionCommand.Menu

    /// The commands in the order of the menu.
    let entries: [Entry]

    var id: SessionCommand.Menu { menu }
  }

  /// The groups, in the order the overview lists them.
  let groups: [Group]

  /// The shortcuts of a window of `kind`.
  init(kind: Session.Kind) {
    groups = Self.menuOrder.compactMap { menu in
      let entries = SessionCommand.groups(in: menu).joined().compactMap { command in
        Self.entry(for: command, in: kind)
      }
      return entries.isEmpty ? nil : Group(menu: menu, entries: entries)
    }
  }

  /// When the single keys work in a window of `kind`: in a merge, wherever one is not typing
  /// in the result; in a comparison, which has none, wherever a pane has the focus.
  static func singleKeyNote(for kind: Session.Kind) -> String {
    switch kind {
    case .merge:
      String(
        localized: "Single keys work wherever you are not typing in the result.", bundle: .module,
        comment: "Keyboard Shortcuts: when the keys without Command work in a merge.")
    case .diff:
      String(
        localized: "Single keys work while a pane has the focus.", bundle: .module,
        comment: "Keyboard Shortcuts: when the keys without Command work in a comparison.")
    }
  }

  /// Go first, since moving through the changes is what one does most, then the decisions.
  private static let menuOrder: [SessionCommand.Menu] = [.go, .merge, .compare, .view, .file]

  /// The commands that only a merge has: a comparison has neither conflicts nor a result.
  private static let mergeCommands: Set<SessionCommand> = Set(
    SessionCommand.groups(in: .merge).joined()
  ).union([.nextConflict, .previousConflict, .toggleBase, .toggleResultMaximized])

  /// The commands that only a comparison has: a merge takes the text of a side with Use A and
  /// Use B.
  private static let comparisonCommands: Set<SessionCommand> = [
    .copyToRight, .copyToLeft, .copyAllChangesToRight, .copyAllChangesToLeft,
  ]

  private static func entry(for command: SessionCommand, in kind: Session.Kind) -> Entry? {
    if kind == .diff && mergeCommands.contains(command) { return nil }
    if kind == .merge && comparisonCommands.contains(command) { return nil }
    let shortcut = command.keyEquivalent(in: kind).map { symbols(for: $0.key, $0.modifiers) }
    let singleKeys = singleKeys(of: command, in: kind)
    guard shortcut != nil || singleKeys != nil else { return nil }
    return Entry(command: command, shortcut: shortcut, singleKeys: singleKeys)
  }

  /// The keys of block mode, each told only once: Shift-Tab arrives as two characters.
  private static func singleKeys(of command: SessionCommand, in kind: Session.Kind) -> String? {
    var spelled: [String] = []
    for keystroke in command.blockModeKeys(in: kind) {
      let symbol = symbols(for: keystroke.key, keystroke.modifiers)
      if !spelled.contains(symbol) {
        spelled.append(symbol)
      }
    }
    switch spelled.count {
    case 0: return nil
    case 1: return spelled[0]
    default:
      precondition(spelled.count == 2, "A command has at most two single keys")
      return String(
        localized: "\(spelled[0]) or \(spelled[1])", bundle: .module,
        comment: "Keyboard Shortcuts: two single keys that do the same, such as “1 or ←”.")
    }
  }

  /// A key with its modifiers in the symbols and order of the menus: ⌃⌥⇧⌘, then the key.
  ///
  /// A brace is the bracket key with Shift, as the keyboard has it.
  static func symbols(for key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
    var modifiers = modifiers
    var key = key
    if let bracket = shiftedKeys[key] {
      modifiers.insert(.shift)
      key = bracket
    }
    let flags: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    let prefix = flags.filter { modifiers.contains($0.0) }.map(\.1).joined()
    return prefix + (keySymbols[key] ?? key.uppercased())
  }

  /// The keys that are another key with Shift, by the key without it.
  private static let shiftedKeys = ["{": "[", "}": "]"]

  private static let keySymbols: [String: String] = [
    SessionCommand.upArrow: "↑", SessionCommand.downArrow: "↓",
    SessionCommand.leftArrow: "←", SessionCommand.rightArrow: "→",
    SessionCommand.backspace: "⌫", SessionCommand.home: "↖", SessionCommand.end: "↘",
    SessionCommand.tab: "⇥", SessionCommand.backTab: "⇥", "\r": "↩", "\u{3}": "⌤",
  ]
}

extension SessionCommand.Menu {
  /// The title of the menu in the menu bar.
  var title: String {
    switch self {
    case .file: String(localized: "File", bundle: .module, comment: "Menu bar.")
    case .edit: String(localized: "Edit", bundle: .module, comment: "Menu bar.")
    case .view: String(localized: "View", bundle: .module, comment: "Menu bar.")
    case .go: String(localized: "Go", bundle: .module, comment: "Menu bar.")
    case .compare:
      String(localized: "Compare", bundle: .module, comment: "Menu bar: the comparison modes.")
    case .merge:
      String(localized: "Merge", bundle: .module, comment: "Menu bar: the decisions of a merge.")
    }
  }
}
