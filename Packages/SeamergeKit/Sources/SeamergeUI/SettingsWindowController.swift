import AppKit
import SwiftUI

/// Whether the app checks for new versions by itself, as the window Settings shows and changes
/// it; the app keeps it in step with its updater.
@MainActor
public protocol AutomaticUpdateSetting: AnyObject, Observable {
  /// Whether the app asks once a day whether a new version exists.
  var checksAutomatically: Bool { get set }
}

/// The window Settings, which the app menu opens: one form, without panes to switch between,
/// since there is little to set.
@MainActor
public final class SettingsWindowController: NSWindowController {
  /// The settings the window shows and changes.
  public let settings: UserSettings

  /// Creates the window for `settings` and, if the app checks for updates, `updates`, which the
  /// window shows in a group of its own below the others.
  public init(settings: UserSettings, updates: (any AutomaticUpdateSetting)? = nil) {
    self.settings = settings
    let hosting = NSHostingController(
      rootView: SettingsView(
        settings: settings, fontFamilies: UserSettings.monospacedFamilies, updates: updates))
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable]
    window.title = String(
      localized: "Settings", bundle: .module, comment: "Title of the window Settings.")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior.insert(.fullScreenNone)
    super.init(window: window)
    window.setContentSize(hosting.view.fittingSize)
    window.center()
  }

  /// Settings windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }
}
