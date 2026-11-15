import AppKit
import SeamergeUI

/// File > Open Recent: the comparisons last opened from the window Compare Files, up to ten, those
/// of folders with a folder symbol, and Clear Menu, which forgets them here and in the window.
@MainActor
final class RecentComparisonsMenu: NSObject {
  /// The submenu of File > Open Recent.
  let menu = NSMenu(title: MainMenu.Titles.openRecent)

  /// Called with the comparison the user chose.
  var onOpen: ((FileComparison) -> Void)?

  private let recentComparisons: RecentComparisons

  /// Creates the menu of the comparisons of `recentComparisons`.
  init(recentComparisons: RecentComparisons) {
    self.recentComparisons = recentComparisons
    super.init()
    menu.delegate = self
    menuNeedsUpdate(menu)
  }

  @objc private func openComparison(_ sender: NSMenuItem) {
    guard let comparison = sender.representedObject as? FileComparison else { return }
    onOpen?(comparison)
  }

  @objc private func clearMenu(_ sender: Any?) {
    recentComparisons.clear()
  }
}

extension RecentComparisonsMenu: NSMenuDelegate {
  /// Lists the comparisons as they are now, each with the folder its files share.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    for comparison in recentComparisons.comparisons {
      let item = NSMenuItem(
        title: comparison.title, action: #selector(openComparison(_:)), keyEquivalent: "")
      item.subtitle = comparison.folder
      if comparison.comparesFolders {
        item.image = NSImage(
          systemSymbolName: "folder", accessibilityDescription: MainMenu.Titles.folderComparison)
      }
      item.target = self
      item.representedObject = comparison
      menu.addItem(item)
    }
    if !menu.items.isEmpty {
      menu.addItem(.separator())
    }
    let clear = NSMenuItem(
      title: MainMenu.Titles.clearMenu, action: #selector(clearMenu(_:)), keyEquivalent: "")
    clear.target = self
    menu.addItem(clear)
  }
}

extension RecentComparisonsMenu: NSMenuItemValidation {
  /// A comparison works whenever it is listed; Clear Menu, when there is a comparison.
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(openComparison(_:)):
      item.representedObject is FileComparison
    case #selector(clearMenu(_:)):
      !recentComparisons.comparisons.isEmpty
    default:
      false
    }
  }
}
