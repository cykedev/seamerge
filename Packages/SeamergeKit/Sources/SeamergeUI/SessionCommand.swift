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
    default:
      nil
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
    case .copyBlock: #selector(SessionWindowController.copyBlock(_:))
    }
  }

  /// The command whose action is `action`, if any.
  init?(action: Selector?) {
    guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
    self = command
  }
}
