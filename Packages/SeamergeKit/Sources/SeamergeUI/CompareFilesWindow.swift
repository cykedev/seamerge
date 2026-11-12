import AppKit

/// The window of Compare Files: titled after what it does, of fixed size, without a toolbar and
/// without full screen.
final class CompareFilesWindow: NSWindow {
  /// Creates the window, laid out once its content is set.
  init() {
    super.init(
      contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered,
      defer: true)
    title = String(
      localized: "Compare Files", bundle: .module,
      comment: "The title of the window that puts files together to compare or merge.")
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
