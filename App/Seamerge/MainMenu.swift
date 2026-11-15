import AppKit
import MergeModel
import SeamergeUI

/// The main menu of the app, built in code in the order and the words of the concept of the
/// menus.
///
/// The commands of the session window come from ``SessionCommand``, with the action that the
/// window carries out and validates, so that a command works only where it has an effect. A
/// command that the app does not carry out yet has no action, which leaves it deactivated
/// rather than hidden.
@MainActor
final class MainMenu {
  /// The menu bar.
  let menu = NSMenu()

  /// The Window menu, which the app fills with its windows.
  let windowsMenu: NSMenu

  /// The Help menu, which the system adds its search to.
  let helpMenu: NSMenu

  /// The Services menu of the app menu.
  let servicesMenu = NSMenu()

  /// The menu item of each command of the session window.
  private(set) var commandItems: [SessionCommand: NSMenuItem] = [:]

  /// The last item of the File menu, Leave Unresolved, which a comparison calls Skip Remaining
  /// Files; it is the item of both commands.
  let leaveUnresolvedItem: NSMenuItem

  /// Builds the menu bar with `openRecentMenu` as File > Open Recent, keyed as in a merge window.
  init(openRecentMenu: NSMenu) {
    leaveUnresolvedItem = Self.item(SessionCommand.leaveUnresolved.title, key: ".")
    commandItems[.leaveUnresolved] = leaveUnresolvedItem
    commandItems[.skipRemainingFiles] = leaveUnresolvedItem
    windowsMenu = NSMenu(title: Titles.window)
    helpMenu = NSMenu(title: Titles.help)
    for submenu in [
      appMenu(), fileMenu(openRecentMenu: openRecentMenu), editMenu(), viewMenu(), goMenu(),
      compareMenu(), mergeMenu(), windowMenu(), helpMenuContent(),
    ] {
      let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
      item.submenu = submenu
      menu.addItem(item)
    }
    update(for: .merge)
  }

  /// Gives the commands the key equivalents and the names they have in a window of `kind`.
  ///
  /// The last item of the File menu skips the remaining files in a comparison and leaves the
  /// file unresolved in a merge.
  func update(for kind: Session.Kind) {
    for (command, item) in commandItems where item !== leaveUnresolvedItem {
      let key = command.keyEquivalent(in: kind)
      item.keyEquivalent = key?.key ?? ""
      item.keyEquivalentModifierMask = key?.modifiers ?? []
    }
    let command: SessionCommand = kind == .diff ? .skipRemainingFiles : .leaveUnresolved
    leaveUnresolvedItem.title = command.title
    leaveUnresolvedItem.action = command.action
    leaveUnresolvedItem.toolTip = command.help
  }

  private func appMenu() -> NSMenu {
    let services = NSMenuItem(title: Titles.services, action: nil, keyEquivalent: "")
    services.submenu = servicesMenu
    return Self.menu(
      Titles.app,
      [
        [Self.item(Titles.about, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))],
        [
          Self.item(Titles.settings, #selector(AppDelegate.showSettings(_:)), key: ","),
          Self.item(
            Titles.setUpGitIntegration, #selector(AppDelegate.showGitIntegration(_:))),
        ],
        [services],
        [
          Self.item(Titles.hide, #selector(NSApplication.hide(_:)), key: "h"),
          Self.item(
            Titles.hideOthers, #selector(NSApplication.hideOtherApplications(_:)), key: "h",
            modifiers: [.option, .command]),
          Self.item(Titles.showAll, #selector(NSApplication.unhideAllApplications(_:))),
        ],
        [Self.item(Titles.quit, #selector(NSApplication.terminate(_:)), key: "q")],
      ])
  }

  private func fileMenu(openRecentMenu: NSMenu) -> NSMenu {
    let openRecent = NSMenuItem(title: Titles.openRecent, action: nil, keyEquivalent: "")
    openRecent.submenu = openRecentMenu
    return Self.menu(
      Titles.file,
      [
        [
          Self.item(Titles.compareFiles, #selector(AppDelegate.showCompareFiles(_:)), key: "o"),
          openRecent,
        ] + commands(.changeFiles),
        commands(.openInEditor),
        [Self.item(Titles.close, #selector(NSWindow.performClose(_:)), key: "w")]
          + commands(.save, .saveAs, .saveAndClose),
        [
          Self.submenu(ResultFormatChoice.encodingMenuTitle, of: ResultFormatChoice.encodings),
          Self.submenu(ResultFormatChoice.lineEndingMenuTitle, of: ResultFormatChoice.lineEndings),
        ],
        [leaveUnresolvedItem],
      ])
  }

  private func editMenu() -> NSMenu {
    Self.menu(
      Titles.edit,
      [
        [
          Self.item(Titles.undo, #selector(UndoActions.undo(_:)), key: "z"),
          Self.item(
            Titles.redo, #selector(UndoActions.redo(_:)), key: "z", modifiers: [.shift, .command]),
        ],
        [
          Self.item(Titles.cut, #selector(NSText.cut(_:)), key: "x"),
          Self.item(Titles.copy, #selector(NSText.copy(_:)), key: "c"),
          Self.item(Titles.paste, #selector(NSText.paste(_:)), key: "v"),
          Self.item(Titles.selectAll, #selector(NSText.selectAll(_:)), key: "a"),
        ],
        commands(.copyBlock),
        [findItem()],
      ])
  }

  private func findItem() -> NSMenuItem {
    let find = NSMenuItem(title: Titles.find, action: nil, keyEquivalent: "")
    let action = #selector(NSTextView.performFindPanelAction(_:))
    let entries: [(String, String, NSEvent.ModifierFlags, NSFindPanelAction)] = [
      (Titles.findEllipsis, "f", [.command], .showFindPanel),
      (Titles.findNext, "g", [.command], .next),
      (Titles.findPrevious, "g", [.shift, .command], .previous),
      (Titles.useSelectionForFind, "e", [.command], .setFindString),
    ]
    let submenu = NSMenu(title: Titles.find)
    for (title, key, modifiers, tag) in entries {
      let item = Self.item(title, action, key: key, modifiers: modifiers)
      item.tag = Int(tag.rawValue)
      submenu.addItem(item)
    }
    submenu.addItem(
      Self.item(
        Titles.jumpToSelection, #selector(NSText.centerSelectionInVisibleArea(_:)), key: "j"))
    find.submenu = submenu
    return find
  }

  private func viewMenu() -> NSMenu {
    Self.menu(
      Titles.view,
      [
        commands(.toggleBase, .toggleResultMaximized),
        commands(.toggleScrollSynchronization, .toggleLineAlignment, .toggleSyntaxHighlighting)
          + [Self.syntaxSubmenu()]
          + commands(
            .toggleInvisibles, .toggleLineWrapping, .toggleIgnoredChanges, .showAllLines,
            .collapseUnchangedLines),
        commands(.zoomIn, .zoomOut, .actualSize),
        commands(.toggleFooter),
        [
          Self.item(
            Titles.showSidebar, #selector(NSSplitViewController.toggleSidebar(_:)), key: "s",
            modifiers: [.control, .command])
        ],
        [
          Self.item(
            Titles.showToolbar, #selector(NSWindow.toggleToolbarShown(_:)), key: "t",
            modifiers: [.option, .command]),
          Self.item(
            Titles.customizeToolbar, #selector(NSWindow.runToolbarCustomizationPalette(_:))),
        ],
        [
          Self.item(
            Titles.enterFullScreen, #selector(NSWindow.toggleFullScreen(_:)), key: "f",
            modifiers: [.control, .command])
        ],
      ])
  }

  private func goMenu() -> NSMenu {
    Self.menu(Titles.go, SessionCommand.groups(in: .go).map { commands($0) })
  }

  /// The Compare menu, whose Swap Sides also swaps the outer files of the window Compare Files,
  /// which has an action of the same name.
  private func compareMenu() -> NSMenu {
    Self.menu(Titles.compare, SessionCommand.groups(in: .compare).map { commands($0) })
  }

  /// The Merge menu, whose commands that switch a source stand in a submenu of their own.
  private func mergeMenu() -> NSMenu {
    Self.menu(Titles.merge, SessionCommand.groups(in: .merge).map(itemsGatheringSubmenus))
  }

  /// The items of `commands`, with each run of commands that share a submenu gathered into an
  /// item of that submenu.
  private func itemsGatheringSubmenus(_ commands: [SessionCommand]) -> [NSMenuItem] {
    var items: [NSMenuItem] = []
    for (command, item) in zip(commands, self.commands(commands)) {
      guard let title = command.submenuTitle else {
        items.append(item)
        continue
      }
      if let last = items.last, let submenu = last.submenu, submenu.title == title {
        submenu.addItem(item)
      } else {
        let submenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenuItem.submenu = NSMenu(title: title)
        submenuItem.submenu?.addItem(item)
        items.append(submenuItem)
      }
    }
    return items
  }

  private func windowMenu() -> NSMenu {
    for group in [
      [
        Self.item(Titles.minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
        Self.item(Titles.zoom, #selector(NSWindow.performZoom(_:))),
      ],
      [Self.item(Titles.bringAllToFront, #selector(NSApplication.arrangeInFront(_:)))],
    ] {
      if !windowsMenu.items.isEmpty {
        windowsMenu.addItem(.separator())
      }
      for item in group {
        windowsMenu.addItem(item)
      }
    }
    return windowsMenu
  }

  private func helpMenuContent() -> NSMenu {
    for item in [
      Self.item(Titles.seamergeHelp),
      Self.item(Titles.keyboardShortcuts, #selector(AppDelegate.showKeyboardShortcuts(_:))),
    ] {
      helpMenu.addItem(item)
    }
    return helpMenu
  }

  /// The items of `commands`, kept to give them the keys of each kind of window.
  private func commands(_ commands: SessionCommand...) -> [NSMenuItem] {
    self.commands(commands)
  }

  private func commands(_ commands: [SessionCommand]) -> [NSMenuItem] {
    commands.map { command in
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      item.toolTip = command.help
      commandItems[command] = item
      return item
    }
  }

  /// An item of a submenu titled `title` of the items of `choices`.
  private static func submenu(_ title: String, of choices: [ResultFormatChoice]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    for choice in choices {
      submenu.addItem(choice.menuItem())
    }
    item.submenu = submenu
    return item
  }

  /// The submenu Syntax of the choices of the language the code is colored as.
  private static func syntaxSubmenu() -> NSMenuItem {
    let item = NSMenuItem(title: SyntaxChoice.menuTitle, action: nil, keyEquivalent: "")
    item.submenu = menu(
      SyntaxChoice.menuTitle, SyntaxChoice.groups.map { $0.map { $0.menuItem() } })
    return item
  }

  /// A menu titled `title` of `groups` of items, with a separator between groups.
  private static func menu(_ title: String, _ groups: [[NSMenuItem]]) -> NSMenu {
    let menu = NSMenu(title: title)
    for (index, group) in groups.enumerated() {
      if index > 0 {
        menu.addItem(.separator())
      }
      for item in group {
        menu.addItem(item)
      }
    }
    return menu
  }

  /// An item that sends `action`; without one, the item stays deactivated.
  private static func item(
    _ title: String, _ action: Selector? = nil, key: String = "",
    modifiers: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
    return item
  }

}

/// The actions of Undo and Redo, which the window and the text views carry out for their undo
/// manager; AppKit declares them for no class.
@objc private protocol UndoActions {
  func undo(_ sender: Any?)
  func redo(_ sender: Any?)
}
