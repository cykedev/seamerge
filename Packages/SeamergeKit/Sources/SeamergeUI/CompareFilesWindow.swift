import AppKit

/// The window of a sheet of files, which takes the size of its content and the title of what the
/// sheet is for.
final class CompareFilesWindow: NSWindow {
  /// Creates the window, laid out once its content is set.
  init() {
    super.init(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    isReleasedWhenClosed = false
    isRestorable = false
    autorecalculatesKeyViewLoop = true
  }
}
