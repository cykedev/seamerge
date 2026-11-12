import Foundation

extension MainMenu {
  /// The names of the menus and of the items that are not commands of the session window.
  enum Titles {
    static let app = String(localized: "Seamerge", comment: "Menu bar: the app menu.")
    static let about = String(localized: "About Seamerge", comment: "App menu.")
    static let settings = String(localized: "Settings…", comment: "App menu.")
    static let setUpGitIntegration = String(
      localized: "Set Up Git Integration…", comment: "App menu: make Git use Seamerge.")
    static let services = String(localized: "Services", comment: "App menu.")
    static let hide = String(localized: "Hide Seamerge", comment: "App menu.")
    static let hideOthers = String(localized: "Hide Others", comment: "App menu.")
    static let showAll = String(localized: "Show All", comment: "App menu.")
    static let quit = String(localized: "Quit Seamerge", comment: "App menu.")

    static let file = String(localized: "File", comment: "Menu bar.")
    static let compareFiles = String(
      localized: "Compare Files…", comment: "File menu: open the window Compare Files.")
    static let openRecent = String(localized: "Open Recent", comment: "File menu.")
    static let clearMenu = String(
      localized: "Clear Menu", comment: "File > Open Recent: forget the recent comparisons.")
    static let close = String(localized: "Close", comment: "File menu.")
    static let save = String(localized: "Save", comment: "File menu.")
    static let saveAs = String(localized: "Save As…", comment: "File menu.")
    static let saveAndClose = String(localized: "Save and Close", comment: "File menu.")
    static let leaveUnresolved = String(
      localized: "Leave Unresolved", comment: "File menu: close a merge without saving it.")
    static let skipRemainingFiles = String(
      localized: "Skip Remaining Files",
      comment: "File menu of a comparison: end the comparisons that Git has left.")

    static let edit = String(localized: "Edit", comment: "Menu bar.")
    static let undo = String(localized: "Undo", comment: "Edit menu.")
    static let redo = String(localized: "Redo", comment: "Edit menu.")
    static let cut = String(localized: "Cut", comment: "Edit menu.")
    static let copy = String(localized: "Copy", comment: "Edit menu.")
    static let paste = String(localized: "Paste", comment: "Edit menu.")
    static let selectAll = String(localized: "Select All", comment: "Edit menu.")
    static let find = String(localized: "Find", comment: "Edit menu: the submenu of finding.")
    static let findEllipsis = String(localized: "Find…", comment: "Edit > Find.")
    static let findNext = String(localized: "Find Next", comment: "Edit > Find.")
    static let findPrevious = String(localized: "Find Previous", comment: "Edit > Find.")
    static let useSelectionForFind = String(
      localized: "Use Selection for Find", comment: "Edit > Find.")
    static let jumpToSelection = String(localized: "Jump to Selection", comment: "Edit > Find.")

    static let view = String(localized: "View", comment: "Menu bar.")
    static let syntaxHighlighting = String(
      localized: "Syntax Highlighting", comment: "View menu: color the code by its syntax.")
    static let showIgnoredChanges = String(
      localized: "Show Ignored Changes",
      comment: "View menu: mark the differences the comparison mode ignores.")
    static let showToolbar = String(localized: "Show Toolbar", comment: "View menu.")
    static let customizeToolbar = String(localized: "Customize Toolbar…", comment: "View menu.")
    static let enterFullScreen = String(localized: "Enter Full Screen", comment: "View menu.")

    static let go = String(localized: "Go", comment: "Menu bar.")
    static let compare = String(localized: "Compare", comment: "Menu bar: the comparison modes.")
    static let swapSides = String(
      localized: "Swap Sides", comment: "Compare menu: swap the left and the right file.")

    static let merge = String(localized: "Merge", comment: "Menu bar: the decisions of a merge.")
    static let useA = String(localized: "Use A", comment: "Merge menu.")
    static let useBase = String(localized: "Use Base", comment: "Merge menu.")
    static let useB = String(localized: "Use B", comment: "Merge menu.")
    static let useAThenB = String(localized: "Use A Then B", comment: "Merge menu.")
    static let useBThenA = String(localized: "Use B Then A", comment: "Merge menu.")
    static let useNone = String(localized: "Use None", comment: "Merge menu.")
    static let toggleSource = String(
      localized: "Toggle Source", comment: "Merge menu: the submenu that adds or removes a side.")
    static let sourceA = String(localized: "A", comment: "Merge > Toggle Source.")
    static let sourceBase = String(localized: "Base", comment: "Merge > Toggle Source.")
    static let sourceB = String(localized: "B", comment: "Merge > Toggle Source.")
    static let resolveManually = String(localized: "Resolve Manually", comment: "Merge menu.")
    static let resetThisChange = String(localized: "Reset This Change", comment: "Merge menu.")
    static let reopenAllConflicts = String(
      localized: "Reopen All Conflicts", comment: "Merge menu.")
    static let resetAllDecisions = String(
      localized: "Reset All Decisions…", comment: "Merge menu.")
    static let resolveAllWithA = String(
      localized: "Resolve All Open Conflicts with A", comment: "Merge menu.")
    static let resolveAllWithB = String(
      localized: "Resolve All Open Conflicts with B", comment: "Merge menu.")

    static let window = String(localized: "Window", comment: "Menu bar.")
    static let minimize = String(localized: "Minimize", comment: "Window menu.")
    static let zoom = String(localized: "Zoom", comment: "Window menu.")
    static let bringAllToFront = String(localized: "Bring All to Front", comment: "Window menu.")

    static let help = String(localized: "Help", comment: "Menu bar.")
    static let seamergeHelp = String(localized: "Seamerge Help", comment: "Help menu.")
    static let keyboardShortcuts = String(
      localized: "Keyboard Shortcuts", comment: "Help menu: the sheet of all shortcuts.")
  }
}
