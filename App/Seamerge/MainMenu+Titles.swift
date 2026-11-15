import Foundation

extension MainMenu {
  /// The names of the menus and of the items that are not commands of the session window.
  enum Titles {
    static let app = String(localized: "Seamerge", comment: "Menu bar: the app menu.")
    static let about = String(localized: "About Seamerge", comment: "App menu.")
    static let checkForUpdates = String(
      localized: "Check for Updates…", comment: "App menu: look for a new version of the app.")
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
    static let compareFolders = String(
      localized: "Compare Folders…",
      comment: "File menu: open the window Compare Files to choose two folders.")
    static let openRecent = String(localized: "Open Recent", comment: "File menu.")
    static let folderComparison = String(
      localized: "Folders", comment: "VoiceOver: the symbol of a recent comparison of two folders.")
    static let clearMenu = String(
      localized: "Clear Menu", comment: "File > Open Recent: forget the recent comparisons.")
    static let close = String(localized: "Close", comment: "File menu.")

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
    static let showSidebar = String(
      localized: "Show Sidebar", comment: "View menu: show the list of the files of a window.")
    static let showToolbar = String(localized: "Show Toolbar", comment: "View menu.")
    static let customizeToolbar = String(localized: "Customize Toolbar…", comment: "View menu.")
    static let enterFullScreen = String(localized: "Enter Full Screen", comment: "View menu.")

    static let go = String(localized: "Go", comment: "Menu bar.")
    static let compare = String(localized: "Compare", comment: "Menu bar: the comparison modes.")

    static let merge = String(localized: "Merge", comment: "Menu bar: the decisions of a merge.")

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
