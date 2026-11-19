public import AppKit
public import MergeModel
import SwiftUI

/// The window Keyboard Shortcuts, which the Help menu opens: every shortcut of a merge or of a
/// comparison at a glance.
@MainActor
public final class ShortcutOverviewWindowController: NSWindowController {
  /// Creates the window, showing the shortcuts of a window of `kind` first.
  public init(kind: Session.Kind) {
    let hosting = NSHostingController(rootView: ShortcutOverviewView(kind: kind))
    hosting.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable]
    window.title = String(
      localized: "Keyboard Shortcuts", bundle: .module,
      comment: "Title of the window of all keyboard shortcuts.")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior.insert(.fullScreenNone)
    super.init(window: window)
    window.setContentSize(hosting.view.fittingSize)
    window.center()
  }

  /// Overview windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }
}
