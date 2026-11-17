import AppKit

/// The welcome window: of fixed size, without a toolbar and without full screen, with its
/// content under a title bar that shows only its buttons.
///
/// Its title, Welcome, names what the window is, in the Window menu and for VoiceOver, as the
/// title bar does not show it.
final class WelcomeWindow: NSWindow {
  /// Creates the window, laid out once its content is set.
  init() {
    super.init(
      contentRect: CGRect(origin: .zero, size: WelcomeMetrics.contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered,
      defer: true)
    title = String(
      localized: "Welcome", bundle: .module,
      comment:
        "The title of the window that starts a comparison or a merge and lists the recent ones; shown in the Window menu, not in the title bar."
    )
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isReleasedWhenClosed = false
    isRestorable = false
    tabbingMode = .disallowed
    collectionBehavior = [.fullScreenNone]
    autorecalculatesKeyViewLoop = true
  }

  /// Lets the list of recent comparisons open its selected line with Return, which would
  /// otherwise go to the default button.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let list = firstResponder as? RecentComparisonsTableView, list.handleReturn(event) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
