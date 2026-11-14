import AppKit
import SwiftUI

/// The window Settings, which the app menu opens: one form, without panes to switch between,
/// since there is little to set.
@MainActor
public final class SettingsWindowController: NSWindowController {
  /// The settings the window shows and changes.
  public let settings: UserSettings

  /// Creates the window for `settings`.
  public init(settings: UserSettings) {
    self.settings = settings
    let hosting = NSHostingController(
      rootView: SettingsView(
        settings: settings, fontFamilies: UserSettings.monospacedFamilies))
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
