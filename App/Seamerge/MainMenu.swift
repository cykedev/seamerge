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
  /// Files.
  let leaveUnresolvedItem: NSMenuItem

  /// Builds the menu bar with `openRecentMenu` as File > Open Recent, keyed as in a merge window.
  init(openRecentMenu: NSMenu) {
    leaveUnresolvedItem = Self.item(Titles.leaveUnresolved, key: ".")
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
  func update(for kind: Session.Kind) {
    for (command, item) in commandItems {
      let key = command.keyEquivalent(in: kind)
      item.keyEquivalent = key?.key ?? ""
      item.keyEquivalentModifierMask = key?.modifiers ?? []
    }
    leaveUnresolvedItem.title = kind == .diff ? Titles.skipRemainingFiles : Titles.leaveUnresolved
  }

  private func appMenu() -> NSMenu {
    let services = NSMenuItem(title: Titles.services, action: nil, keyEquivalent: "")
    services.submenu = servicesMenu
    return Self.menu(
      Titles.app,
      [
        [Self.item(Titles.about, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))],
        [Self.item(Titles.settings, key: ","), Self.item(Titles.setUpGitIntegration)],
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
        ],
        commands(.openInEditor),
        [
          Self.item(Titles.close, #selector(NSWindow.performClose(_:)), key: "w"),
          Self.item(Titles.save, key: "s"), Self.item(Titles.saveAs),
          Self.item(Titles.saveAndClose, key: "\r"),
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
        commands(.toggleScrollSynchronization) + [Self.item(Titles.syntaxHighlighting)]
          + commands(.toggleInvisibles) + [Self.item(Titles.showIgnoredChanges)]
          + commands(.toggleCollapsedLines),
        commands(.zoomIn, .zoomOut, .actualSize),
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

  private func compareMenu() -> NSMenu {
    Self.menu(
      Titles.compare,
      SessionCommand.groups(in: .compare).map { commands($0) } + [
        [
          Self.item(
            Titles.swapSides, #selector(CompareFilesWindowController.swapSides(_:)), key: "s",
            modifiers: [.option, .command])
        ]
      ])
  }

  private func mergeMenu() -> NSMenu {
    let toggleSource = NSMenuItem(title: Titles.toggleSource, action: nil, keyEquivalent: "")
    toggleSource.submenu = Self.menu(
      Titles.toggleSource,
      [
        [
          Self.item(Titles.sourceA, key: "1", modifiers: [.option, .command]),
          Self.item(Titles.sourceBase, key: "2", modifiers: [.option, .command]),
          Self.item(Titles.sourceB, key: "3", modifiers: [.option, .command]),
        ]
      ])
    return Self.menu(
      Titles.merge,
      [
        [
          Self.item(Titles.useA, key: "1"), Self.item(Titles.useBase, key: "2"),
          Self.item(Titles.useB, key: "3"), Self.item(Titles.useAThenB, key: "4"),
          Self.item(Titles.useBThenA, key: "5"), Self.item(Titles.useNone, key: "6"),
          toggleSource, Self.item(Titles.resolveManually),
        ],
        [
          Self.item(Titles.resetThisChange, key: Self.backspace, modifiers: [.option, .command]),
          Self.item(Titles.reopenAllConflicts),
          Self.item(
            Titles.resetAllDecisions, key: Self.backspace, modifiers: [.shift, .option, .command]),
        ],
        [Self.item(Titles.resolveAllWithA), Self.item(Titles.resolveAllWithB)],
      ])
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
    for item in [Self.item(Titles.seamergeHelp), Self.item(Titles.keyboardShortcuts)] {
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

  /// The character AppKit gives the Delete key.
  private static let backspace = "\u{8}"
}

/// The actions of Undo and Redo, which the window and the text views carry out for their undo
/// manager; AppKit declares them for no class.
@objc private protocol UndoActions {
  func undo(_ sender: Any?)
  func redo(_ sender: Any?)
}
