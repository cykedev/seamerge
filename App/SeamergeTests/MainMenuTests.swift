import AppKit
import MergeModel
import SeamergeUI
import Testing

/// The main menu: every command of the concept in its words with its key, the actions of the
/// session window, and what changes with the kind of window.
@MainActor
@Suite struct MainMenuTests {
  @Test func everyCommandStandsInItsMenuInTheWordsAndWithTheKeysOfTheConcept() throws {
    let menu = MainMenu(openRecentMenu: NSMenu())

    let outline = Self.outline(of: menu.menu)

    try write(outline, named: "main-menu.txt")
    #expect(outline == Self.expectedOutline)
  }

  @Test func commandsOfTheSessionWindowSendItsActionsInTheOrderOfTheirGroups() throws {
    let mainMenu = MainMenu(openRecentMenu: NSMenu())
    let menus: [(SessionCommand.Menu, String)] = [
      (.file, "File"), (.edit, "Edit"), (.view, "View"), (.go, "Go"), (.compare, "Compare"),
      (.merge, "Merge"),
    ]

    for (sessionMenu, title) in menus {
      let items = Self.allItems(of: try #require(mainMenu.menu.item(withTitle: title)?.submenu))
      let commands = SessionCommand.groups(in: sessionMenu).flatMap(\.self)
      let positions = try commands.map { command in
        let item = try #require(mainMenu.commandItems[command], "\(command)")
        // The last item of the File menu is the command of the kind of window in front.
        mainMenu.update(for: command == .skipRemainingFiles ? .diff : .merge)
        #expect(item.action == command.action)
        #expect(item.toolTip == command.help)
        return try #require(items.firstIndex(of: item), "\(command) is not in \(title)")
      }
      #expect(positions == positions.sorted(), "\(title)")
    }
    #expect(mainMenu.commandItems.count == SessionCommand.allCases.count)
  }

  @Test func jumpsAndTheLastFileCommandFollowTheKindOfWindow() throws {
    let mainMenu = MainMenu(openRecentMenu: NSMenu())

    mainMenu.update(for: .diff)

    let item = { (command: SessionCommand) in try #require(mainMenu.commandItems[command]) }
    #expect(try Self.keys(of: item(.nextChange)) == "⌥⌘↓")
    #expect(try Self.keys(of: item(.previousChange)) == "⌥⌘↑")
    #expect(try Self.keys(of: item(.nextConflict)) == "")
    #expect(try Self.keys(of: item(.filterFiles)) == "⇧⌘F")
    #expect(mainMenu.leaveUnresolvedItem.title == "Skip Remaining Files")
    #expect(mainMenu.leaveUnresolvedItem.action == SessionCommand.skipRemainingFiles.action)
    #expect(Self.keys(of: mainMenu.leaveUnresolvedItem) == "⌘.")

    mainMenu.update(for: .merge)

    #expect(try Self.keys(of: item(.nextChange)) == "⌥⇧⌘↓")
    #expect(try Self.keys(of: item(.nextConflict)) == "⌥⌘↓")
    #expect(mainMenu.leaveUnresolvedItem.title == "Leave Unresolved")
    #expect(mainMenu.leaveUnresolvedItem.action == SessionCommand.leaveUnresolved.action)
    #expect(Self.keys(of: mainMenu.leaveUnresolvedItem) == "⌘.")
  }

  @Test func whatHasNoEffectIsDeactivatedAndNothingIsHidden() {
    let menu = MainMenu(openRecentMenu: NSMenu()).menu
    let items = Self.allItems(of: menu)

    for submenu in items.compactMap(\.submenu) {
      submenu.update()
    }

    #expect(items.allSatisfy { !$0.isHidden })
    let commandsWithoutAWindow = items.filter { $0.action != nil && !$0.isEnabled }
    #expect(commandsWithoutAWindow.contains { $0.title == "Next Conflict" })
    #expect(items.filter { $0.action == nil && $0.submenu == nil }.allSatisfy { !$0.isEnabled })
  }

  /// The menu as text: one line per item, indented by its depth, with its keys, and marked when
  /// it has no action yet.
  static func outline(of menu: NSMenu, depth: Int = 0) -> String {
    menu.items.map { item in
      let indent = String(repeating: "  ", count: depth)
      if item.isSeparatorItem {
        return indent + "---"
      }
      var line = indent + item.title
      let keys = keys(of: item)
      if !keys.isEmpty {
        line += " " + keys
      }
      if let submenu = item.submenu {
        let isFilledLater = submenu.items.isEmpty || item.title == "Services"
        return line + " ▸" + (isFilledLater ? "" : "\n" + outline(of: submenu, depth: depth + 1))
      }
      return line + (item.action == nil ? " (deactivated)" : "")
    }.joined(separator: "\n")
  }

  /// The keys of `item` as the menu shows them, modifier keys first.
  static func keys(of item: NSMenuItem) -> String {
    guard !item.keyEquivalent.isEmpty else { return "" }
    let modifiers = item.keyEquivalentModifierMask
    let names: [(NSEvent.ModifierFlags, String)] = [
      (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
    let glyphs = [
      "\u{F700}": "↑", "\u{F701}": "↓", "\t": "⇥", "\r": "↩", "\u{8}": "⌫",
    ]
    let key = glyphs[item.keyEquivalent] ?? item.keyEquivalent.uppercased()
    return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
  }

  private static func allItems(of menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
  }

  private func write(_ text: String, named name: String) throws {
    let folder =
      ProcessInfo.processInfo.environment["SEAMERGE_PICTURES"].map { URL(filePath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "SeamergePictures/App")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data((text + "\n").utf8).write(to: folder.appending(path: name))
  }

  private static let expectedOutline = """
    Seamerge ▸
      About Seamerge
      Check for Updates…
      ---
      Settings… ⌘,
      Set Up Git Integration…
      ---
      Services ▸
      ---
      Hide Seamerge ⌘H
      Hide Others ⌥⌘H
      Show All
      ---
      Quit Seamerge ⌘Q
    File ▸
      Compare Files… ⌘O
      Compare Folders…
      Open Recent ▸
      Change Files…
      ---
      Open in Editor ⌥⌘O
      ---
      Close ⌘W
      Save ⌘S
      Save As…
      Save and Close ⌘↩
      ---
      Result Encoding ▸
        UTF-8
        UTF-16 LE
        UTF-16 BE
        UTF-32 LE
        UTF-32 BE
        Windows 1252
        ISO 8859-1
        Mac Roman
      Line Endings ▸
        LF
        CRLF
        CR
      ---
      Leave Unresolved ⌘.
    Edit ▸
      Undo ⌘Z
      Redo ⇧⌘Z
      ---
      Cut ⌘X
      Copy ⌘C
      Paste ⌘V
      Select All ⌘A
      ---
      Copy Block
      ---
      Find ▸
        Find… ⌘F
        Find Next ⌘G
        Find Previous ⇧⌘G
        Use Selection for Find ⌘E
        Jump to Selection ⌘J
        ---
        Filter Files
    View ▸
      Hide Base ⌥⌘B
      Maximize Result ⌥⌘R
      ---
      Synchronize Scrolling ⌥⌘Y
      Align Lines ⌥⌘A
      Highlight Syntax
      Syntax ▸
        Automatic
        ---
        C
        C#
        C++
        CSS
        Go
        HTML
        Java
        JavaScript
        JSON
        Kotlin
        Markdown
        Objective-C
        PHP
        Python
        Ruby
        Rust
        SCSS
        Shell
        SQL
        Swift
        TOML
        TypeScript
        XML
        YAML
        ---
        Plain Text
      Show Invisibles
      Wrap Lines ⌥⌘L
      Show Ignored Changes
      Show All Lines ⇧⌘L
      Collapse Unchanged Lines ⌥⇧⌘L
      ---
      Zoom In ⌘+
      Zoom Out ⌘-
      Actual Size ⌘0
      ---
      Hide Footer ⌘/
      ---
      Show Sidebar ⌃⌘S
      Show Identical Files
      ---
      Show Toolbar ⌥⌘T
      Customize Toolbar…
      ---
      Enter Full Screen ⌃⌘F
    Go ▸
      Next Conflict ⌥⌘↓
      Previous Conflict ⌥⌘↑
      ---
      Next Change ⌥⇧⌘↓
      Previous Change ⌥⇧⌘↑
      First Change
      Last Change
      ---
      Next File
      Previous File
      ---
      Next Pane ⌃⇥
      Previous Pane ⌃⇧⇥
      ---
      Go to Line… ⌘L
    Compare ▸
      Exact
      Ignore Line Endings
      Ignore Whitespace Changes
      Ignore All Whitespace
      ---
      Swap Sides ⌥⌘S
    Merge ▸
      Use A ⌘1
      Use Base ⌘2
      Use B ⌘3
      Use A Then B ⌘4
      Use B Then A ⌘5
      Use None ⌘6
      Toggle Source ▸
        A ⌥⌘1
        Base ⌥⌘2
        B ⌥⌘3
      Resolve Manually
      ---
      Reset This Change ⌥⌘⌫
      Reopen All Conflicts
      Reset All Decisions… ⌥⇧⌘⌫
      ---
      Resolve All Open Conflicts with A
      Resolve All Open Conflicts with B
    Window ▸
      Minimize ⌘M
      Zoom
      ---
      Bring All to Front
    Help ▸
      Seamerge Help (deactivated)
      Keyboard Shortcuts
    """
}
