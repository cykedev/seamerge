import AppKit
import SwiftUI

/// Whether the app checks for new versions by itself, as the window Settings shows and changes
/// it; the app keeps it in step with its updater.
@MainActor
public protocol AutomaticUpdateSetting: AnyObject, Observable {
  /// Whether the app asks once a day whether a new version exists.
  var checksAutomatically: Bool { get set }
}

/// The window Settings, which the app menu opens, with two pages in its toolbar: General, the
/// form of how the code is drawn and how windows start, and Ignored Text, the ignore rules.
@MainActor
public final class SettingsWindowController: NSWindowController {
  /// The settings the window shows and changes.
  public let settings: UserSettings

  /// The pages of the window.
  let tabs: SettingsTabViewController

  /// The page of the ignore rules.
  let ignoredText: IgnoredTextViewController

  /// Creates the window for `settings` and, if the app checks for updates, `updates`, which the
  /// page General shows in a group of its own below the others.
  public convenience init(settings: UserSettings, updates: (any AutomaticUpdateSetting)? = nil) {
    self.init(settings: settings, updates: updates, displayOptions: .current(in: .shared))
  }

  /// Creates the window for `settings` and `updates`, drawn with `displayOptions`, whatever the
  /// system's settings are.
  init(
    settings: UserSettings, updates: (any AutomaticUpdateSetting)?, displayOptions: DisplayOptions
  ) {
    self.settings = settings
    let general = NSHostingController(
      rootView: SettingsView(
        settings: settings, fontFamilies: UserSettings.monospacedFamilies, updates: updates))
    general.sizingOptions = [.preferredContentSize]
    general.title = String(
      localized: "General", bundle: .module,
      comment: "Settings: the page of the font, new windows, merging and updates.")
    ignoredText = IgnoredTextViewController(settings: settings, displayOptions: displayOptions)
    // The window takes the size of the page in view; with Reduce Motion, the pages cut.
    tabs = SettingsTabViewController(reducesMotion: displayOptions.reducesMotion)
    for (page, symbol) in [(general, "gearshape"), (ignoredText, "eye.slash")]
      as [(NSViewController, String)]
    {
      let item = NSTabViewItem(viewController: page)
      item.label = page.title ?? ""
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      tabs.addTabViewItem(item)
    }
    let window = NSWindow(contentViewController: tabs)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior.insert(.fullScreenNone)
    super.init(window: window)
    // The tab view controller takes the size of the form only once SwiftUI has measured it.
    window.setContentSize(general.view.fittingSize)
    window.center()
  }

  /// Settings windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }
}
