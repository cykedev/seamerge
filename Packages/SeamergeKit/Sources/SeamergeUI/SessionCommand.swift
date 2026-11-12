import AppKit
import MergeModel

/// A command of a session window: its name, the action it sends along the responder chain, its
/// key equivalent and single key, the menu and group it stands in, and what it needs to have an
/// effect.
///
/// The main menu, the context menus, the toolbar and the single keys of block mode all take the
/// commands from here and send the same action, which the window controller carries out and
/// validates; there is no second way to carry out a command. A command is valid only while it
/// can have an effect.
public enum SessionCommand: CaseIterable, Sendable {
  /// Jumps to the next open conflict.
  case nextConflict

  /// Jumps to the previous open conflict.
  case previousConflict

  /// Jumps to the next change.
  case nextChange

  /// Jumps to the previous change.
  case previousChange

  /// Jumps to the first change.
  case firstChange

  /// Jumps to the last change.
  case lastChange

  /// Moves the focus to the next pane: from A over Base and B to the result, and back to A.
  case nextPane

  /// Moves the focus to the previous pane.
  case previousPane

  /// Compares lines byte for byte.
  case compareExactly

  /// Compares lines without their line endings.
  case ignoreLineEndings

  /// Compares lines as equal where they differ only in the amount of whitespace.
  case ignoreWhitespaceChanges

  /// Compares lines without any of their whitespace.
  case ignoreAllWhitespace

  /// Copies the lines of the current block in the pane with the focus, or in the pane of a
  /// context menu.
  case copyBlock

  /// The name of the command in a menu.
  public var title: String {
    switch self {
    case .nextConflict:
      String(localized: "Next Conflict", bundle: .module, comment: "Go menu command.")
    case .previousConflict:
      String(localized: "Previous Conflict", bundle: .module, comment: "Go menu command.")
    case .nextChange:
      String(localized: "Next Change", bundle: .module, comment: "Go menu command.")
    case .previousChange:
      String(localized: "Previous Change", bundle: .module, comment: "Go menu command.")
    case .firstChange:
      String(localized: "First Change", bundle: .module, comment: "Go menu command.")
    case .lastChange:
      String(localized: "Last Change", bundle: .module, comment: "Go menu command.")
    case .nextPane:
      String(localized: "Next Pane", bundle: .module, comment: "Go menu command.")
    case .previousPane:
      String(localized: "Previous Pane", bundle: .module, comment: "Go menu command.")
    case .compareExactly:
      String(localized: "Exact", bundle: .module, comment: "Compare menu: compare every byte.")
    case .ignoreLineEndings:
      String(localized: "Ignore Line Endings", bundle: .module, comment: "Compare menu command.")
    case .ignoreWhitespaceChanges:
      String(
        localized: "Ignore Whitespace Changes", bundle: .module, comment: "Compare menu command.")
    case .ignoreAllWhitespace:
      String(localized: "Ignore All Whitespace", bundle: .module, comment: "Compare menu command.")
    case .copyBlock:
      String(
        localized: "Copy Block", bundle: .module,
        comment: "Edit menu command: copy the lines of the current block.")
    }
  }

  /// The help tag of the command in a menu or the toolbar, or `nil` if its name says it all.
  public var help: String? {
    switch self {
    case .nextConflict:
      String(
        localized: "Go on to the open conflict after this one", bundle: .module,
        comment: "Help tag of Next Conflict.")
    case .previousConflict:
      String(
        localized: "Go back to the open conflict before this one", bundle: .module,
        comment: "Help tag of Previous Conflict.")
    case .nextChange:
      String(
        localized: "Go on to the change after this one", bundle: .module,
        comment: "Help tag of Next Change.")
    case .previousChange:
      String(
        localized: "Go back to the change before this one", bundle: .module,
        comment: "Help tag of Previous Change.")
    case .compareExactly:
      String(
        localized: "Count every difference, whitespace and line endings too", bundle: .module,
        comment: "Help tag of Compare > Exact.")
    case .ignoreLineEndings:
      String(
        localized: "Treat LF, CRLF and CR as equal", bundle: .module,
        comment: "Help tag of Compare > Ignore Line Endings.")
    case .ignoreWhitespaceChanges:
      String(
        localized: "Treat “a  b” as “a b”, but not as “ab”", bundle: .module,
        comment: "Help tag of Compare > Ignore Whitespace Changes, with an example.")
    case .ignoreAllWhitespace:
      String(
        localized: "Treat “a  b” and “ab” as equal", bundle: .module,
        comment: "Help tag of Compare > Ignore All Whitespace, with an example.")
    default:
      nil
    }
  }

  /// The comparison mode that the command chooses, if it is one of the Compare menu.
  var comparisonMode: ComparisonMode? {
    switch self {
    case .compareExactly: .exact
    case .ignoreLineEndings: .ignoreLineEndings
    case .ignoreWhitespaceChanges: .ignoreWhitespaceAmount
    case .ignoreAllWhitespace: .ignoreAllWhitespace
    default: nil
    }
  }

  /// The action the command sends along the responder chain.
  public var action: Selector {
    switch self {
    case .nextConflict: #selector(SessionWindowController.selectNextConflict(_:))
    case .previousConflict: #selector(SessionWindowController.selectPreviousConflict(_:))
    case .nextChange: #selector(SessionWindowController.selectNextChange(_:))
    case .previousChange: #selector(SessionWindowController.selectPreviousChange(_:))
    case .firstChange: #selector(SessionWindowController.selectFirstChange(_:))
    case .lastChange: #selector(SessionWindowController.selectLastChange(_:))
    case .nextPane: #selector(SessionWindowController.selectNextPane(_:))
    case .previousPane: #selector(SessionWindowController.selectPreviousPane(_:))
    case .compareExactly: #selector(SessionWindowController.compareExactly(_:))
    case .ignoreLineEndings: #selector(SessionWindowController.ignoreLineEndings(_:))
    case .ignoreWhitespaceChanges: #selector(SessionWindowController.ignoreWhitespaceChanges(_:))
    case .ignoreAllWhitespace: #selector(SessionWindowController.ignoreAllWhitespace(_:))
    case .copyBlock: #selector(SessionWindowController.copyBlock(_:))
    }
  }

  /// The command whose action is `action`, if any.
  init?(action: Selector?) {
    guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
    self = command
  }
}
