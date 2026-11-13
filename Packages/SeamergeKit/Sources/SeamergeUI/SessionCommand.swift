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

  /// Puts the two files of a comparison the other way round.
  case swapSides

  /// Hides the pane of the base, or shows it again; A and B share its width meanwhile.
  case toggleBase

  /// Gives the result the whole window, or restores the layout.
  case toggleResultMaximized

  /// Turns the coupling of the panes while they scroll off or on.
  case toggleScrollSynchronization

  /// Shows spaces, tabs and line endings as quiet symbols, or hides them.
  case toggleInvisibles

  /// Shows every line, the collapsed runs of unchanged lines expanded.
  case showAllLines

  /// Collapses long runs of unchanged lines again, except where the result is worked on.
  case collapseUnchangedLines

  /// Makes the text larger.
  case zoomIn

  /// Makes the text smaller.
  case zoomOut

  /// Shows the text at its standard size.
  case actualSize

  /// Asks for a line and jumps to it in the pane with the focus.
  case goToLine

  /// Opens the file that the result is written to in the app the system has for its type.
  case openInEditor

  /// Copies the lines of the current block in the pane with the focus, or in the pane of a
  /// context menu.
  case copyBlock

  /// Closes a comparison that `git difftool` started and tells Git to compare no further files.
  case skipRemainingFiles

  /// Takes only A's text for the current block.
  case useA

  /// Takes only the base's text for the current block.
  case useBase

  /// Takes only B's text for the current block.
  case useB

  /// Takes A's text, then B's, for the current block.
  case useAThenB

  /// Takes B's text, then A's, for the current block.
  case useBThenA

  /// Takes nothing for the current block, which leaves it empty.
  case useNone

  /// Adds A's text to the current block after the texts already taken, or takes it out.
  case toggleSourceA

  /// Adds the base's text to the current block after the texts already taken, or takes it out.
  case toggleSourceBase

  /// Adds B's text to the current block after the texts already taken, or takes it out.
  case toggleSourceB

  /// Turns the current block into text to edit by hand and puts the insertion point into it.
  case resolveManually

  /// Resolves every open conflict with A's text.
  case resolveAllWithA

  /// Resolves every open conflict with B's text.
  case resolveAllWithB

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
    case .swapSides:
      String(
        localized: "Swap Sides", bundle: .module,
        comment: "Compare menu: swap the left and the right file.")
    case .toggleBase:
      String(localized: "Hide Base", bundle: .module, comment: "View menu command.")
    case .toggleResultMaximized:
      String(localized: "Maximize Result", bundle: .module, comment: "View menu command.")
    case .toggleScrollSynchronization:
      String(localized: "Synchronize Scrolling", bundle: .module, comment: "View menu command.")
    case .toggleInvisibles:
      String(localized: "Show Invisibles", bundle: .module, comment: "View menu command.")
    case .showAllLines:
      String(localized: "Show All Lines", bundle: .module, comment: "View menu command.")
    case .collapseUnchangedLines:
      String(localized: "Collapse Unchanged Lines", bundle: .module, comment: "View menu command.")
    case .zoomIn: String(localized: "Zoom In", bundle: .module, comment: "View menu command.")
    case .zoomOut: String(localized: "Zoom Out", bundle: .module, comment: "View menu command.")
    case .actualSize:
      String(localized: "Actual Size", bundle: .module, comment: "View menu command.")
    case .goToLine:
      String(localized: "Go to Line…", bundle: .module, comment: "Go menu command.")
    case .openInEditor:
      String(localized: "Open in Editor", bundle: .module, comment: "File menu command.")
    case .copyBlock:
      String(
        localized: "Copy Block", bundle: .module,
        comment: "Edit menu command: copy the lines of the current block.")
    case .skipRemainingFiles:
      String(
        localized: "Skip Remaining Files", bundle: .module,
        comment: "File menu of a comparison: end the comparisons that Git has left.")
    case .useA: String(localized: "Use A", bundle: .module, comment: "Merge menu command.")
    case .useBase: String(localized: "Use Base", bundle: .module, comment: "Merge menu command.")
    case .useB: String(localized: "Use B", bundle: .module, comment: "Merge menu command.")
    case .useAThenB:
      String(localized: "Use A Then B", bundle: .module, comment: "Merge menu command.")
    case .useBThenA:
      String(localized: "Use B Then A", bundle: .module, comment: "Merge menu command.")
    case .useNone: String(localized: "Use None", bundle: .module, comment: "Merge menu command.")
    case .toggleSourceA: Role.a.letter
    case .toggleSourceBase: Role.base.letter
    case .toggleSourceB: Role.b.letter
    case .resolveManually:
      String(localized: "Resolve Manually", bundle: .module, comment: "Merge menu command.")
    case .resolveAllWithA:
      String(
        localized: "Resolve All Open Conflicts with A", bundle: .module,
        comment: "Merge menu command.")
    case .resolveAllWithB:
      String(
        localized: "Resolve All Open Conflicts with B", bundle: .module,
        comment: "Merge menu command.")
    }
  }

  /// The title of the submenu that the command stands in, for the commands that switch a source
  /// on or off, or `nil` for a command in the menu itself.
  public var submenuTitle: String? {
    switch self {
    case .toggleSourceA, .toggleSourceBase, .toggleSourceB:
      String(
        localized: "Toggle Source", bundle: .module,
        comment: "Merge menu: the submenu that adds or removes a side.")
    default:
      nil
    }
  }

  /// What the Undo and Redo commands call the step that the command makes, or `nil` for a
  /// command that makes no step.
  var undoName: String? {
    switch self {
    case .useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone, .resolveManually,
      .resolveAllWithA, .resolveAllWithB:
      title
    case .toggleSourceA:
      String(
        localized: "Toggle A", bundle: .module,
        comment: "Undo menu: A was switched on or off for a block.")
    case .toggleSourceBase:
      String(
        localized: "Toggle Base", bundle: .module,
        comment: "Undo menu: the base was switched on or off for a block.")
    case .toggleSourceB:
      String(
        localized: "Toggle B", bundle: .module,
        comment: "Undo menu: B was switched on or off for a block.")
    default:
      nil
    }
  }

  /// The roles whose texts the command takes for the current block, in order, if it is one of
  /// the commands that choose them: none for Use None.
  var chosenRoles: [Role]? {
    switch self {
    case .useA: [.a]
    case .useBase: [.base]
    case .useB: [.b]
    case .useAThenB: [.a, .b]
    case .useBThenA: [.b, .a]
    case .useNone: []
    default: nil
    }
  }

  /// The role whose toggle the command switches, if it switches one.
  var toggledRole: Role? {
    switch self {
    case .toggleSourceA: .a
    case .toggleSourceBase: .base
    case .toggleSourceB: .b
    default: nil
    }
  }

  /// The command that switches the toggle of `role`.
  static func toggle(_ role: Role) -> SessionCommand {
    switch role {
    case .a: .toggleSourceA
    case .base: .toggleSourceBase
    case .b: .toggleSourceB
    }
  }

  /// The command that takes only the text of `role`.
  static func use(_ role: Role) -> SessionCommand {
    switch role {
    case .a: .useA
    case .base: .useBase
    case .b: .useB
    }
  }

  /// The name of the command while what it switches on is on, for a command whose name changes
  /// with it, such as Show Base after Hide Base.
  var alternateTitle: String? {
    switch self {
    case .toggleBase:
      String(localized: "Show Base", bundle: .module, comment: "View menu command.")
    case .toggleResultMaximized:
      String(localized: "Restore Layout", bundle: .module, comment: "View menu command.")
    case .toggleInvisibles:
      String(localized: "Hide Invisibles", bundle: .module, comment: "View menu command.")
    default:
      nil
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
    case .swapSides:
      String(
        localized: "Show the right file on the left and the left file on the right",
        bundle: .module, comment: "Help tag of Compare > Swap Sides.")
    case .skipRemainingFiles:
      String(
        localized: "Close and compare no more files of this run", bundle: .module,
        comment: "Help tag of File > Skip Remaining Files.")
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
    case .swapSides: #selector(SessionWindowController.swapSides(_:))
    case .toggleBase: #selector(SessionWindowController.toggleBase(_:))
    case .toggleResultMaximized: #selector(SessionWindowController.toggleResultMaximized(_:))
    case .toggleScrollSynchronization:
      #selector(SessionWindowController.toggleScrollSynchronization(_:))
    case .toggleInvisibles: #selector(SessionWindowController.toggleInvisibles(_:))
    case .showAllLines: #selector(SessionWindowController.showAllLines(_:))
    case .collapseUnchangedLines: #selector(SessionWindowController.collapseUnchangedLines(_:))
    case .zoomIn: #selector(SessionWindowController.zoomIn(_:))
    case .zoomOut: #selector(SessionWindowController.zoomOut(_:))
    case .actualSize: #selector(SessionWindowController.actualSize(_:))
    case .goToLine: #selector(SessionWindowController.goToLine(_:))
    case .openInEditor: #selector(SessionWindowController.openInEditor(_:))
    case .copyBlock: #selector(SessionWindowController.copyBlock(_:))
    case .skipRemainingFiles: #selector(SessionWindowController.skipRemainingFiles(_:))
    case .useA: #selector(SessionWindowController.useA(_:))
    case .useBase: #selector(SessionWindowController.useBase(_:))
    case .useB: #selector(SessionWindowController.useB(_:))
    case .useAThenB: #selector(SessionWindowController.useAThenB(_:))
    case .useBThenA: #selector(SessionWindowController.useBThenA(_:))
    case .useNone: #selector(SessionWindowController.useNone(_:))
    case .toggleSourceA: #selector(SessionWindowController.toggleSourceA(_:))
    case .toggleSourceBase: #selector(SessionWindowController.toggleSourceBase(_:))
    case .toggleSourceB: #selector(SessionWindowController.toggleSourceB(_:))
    case .resolveManually: #selector(SessionWindowController.resolveManually(_:))
    case .resolveAllWithA: #selector(SessionWindowController.resolveAllWithA(_:))
    case .resolveAllWithB: #selector(SessionWindowController.resolveAllWithB(_:))
    }
  }

  /// The command whose action is `action`, if any.
  init?(action: Selector?) {
    guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
    self = command
  }
}
