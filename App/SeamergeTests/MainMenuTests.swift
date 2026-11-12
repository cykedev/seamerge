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
    // In a merge, Leave Unresolved has no action yet; the item is Skip Remaining Files in a
    // comparison.
    mainMenu.update(for: .diff)
    let menus: [(SessionCommand.Menu, String)] = [
      (.file, "File"), (.edit, "Edit"), (.view, "View"), (.go, "Go"), (.compare, "Compare"),
    ]

    for (sessionMenu, title) in menus {
      let items = try #require(mainMenu.menu.item(withTitle: title)?.submenu).items
      let commands = SessionCommand.groups(in: sessionMenu).flatMap(\.self)
      let positions = try commands.map { command in
        let item = try #require(mainMenu.commandItems[command], "\(command)")
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
    #expect(mainMenu.leaveUnresolvedItem.title == "Skip Remaining Files")
    #expect(mainMenu.leaveUnresolvedItem.action == SessionCommand.skipRemainingFiles.action)
    #expect(Self.keys(of: mainMenu.leaveUnresolvedItem) == "⌘.")

    mainMenu.update(for: .merge)

    #expect(try Self.keys(of: item(.nextChange)) == "⌥⇧⌘↓")
    #expect(try Self.keys(of: item(.nextConflict)) == "⌥⌘↓")
    #expect(mainMenu.leaveUnresolvedItem.title == "Leave Unresolved")
    #expect(mainMenu.leaveUnresolvedItem.action == nil)
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
      ---
      Settings… ⌘, (deactivated)
      Set Up Git Integration… (deactivated)
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
      Open Recent ▸
      ---
      Open in Editor ⌥⌘O
      ---
      Close ⌘W
      Save ⌘S (deactivated)
      Save As… (deactivated)
      Save and Close ⌘↩ (deactivated)
      ---
      Leave Unresolved ⌘. (deactivated)
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
    View ▸
      Hide Base ⌥⌘B
      Maximize Result ⌥⌘R
      ---
      Synchronize Scrolling ⌥⌘Y
      Syntax Highlighting (deactivated)
      Show Invisibles
      Show Ignored Changes (deactivated)
      Show All Lines ⇧⌘L
      Collapse Unchanged Lines ⌥⇧⌘L
      ---
      Zoom In ⌘+
      Zoom Out ⌘-
      Actual Size ⌘0
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
      Use A ⌘1 (deactivated)
      Use Base ⌘2 (deactivated)
      Use B ⌘3 (deactivated)
      Use A Then B ⌘4 (deactivated)
      Use B Then A ⌘5 (deactivated)
      Use None ⌘6 (deactivated)
      Toggle Source ▸
        A ⌥⌘1 (deactivated)
        Base ⌥⌘2 (deactivated)
        B ⌥⌘3 (deactivated)
      Resolve Manually (deactivated)
      ---
      Reset This Change ⌥⌘⌫ (deactivated)
      Reopen All Conflicts (deactivated)
      Reset All Decisions… ⌥⇧⌘⌫ (deactivated)
      ---
      Resolve All Open Conflicts with A (deactivated)
      Resolve All Open Conflicts with B (deactivated)
    Window ▸
      Minimize ⌘M
      Zoom
      ---
      Bring All to Front
    Help ▸
      Seamerge Help (deactivated)
      Keyboard Shortcuts (deactivated)
    """
}
