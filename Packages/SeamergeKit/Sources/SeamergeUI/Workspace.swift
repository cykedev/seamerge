import AppKit

/// What a session window asks of the workspace: to open a file in the app the system has for
/// its type, and to show a file in the Finder.
///
/// `NSWorkspace` does both; the window takes the workspace when it is made.
@MainActor
protocol Workspace: AnyObject {
  /// Opens `url` in the default app for its type and tells whether that worked.
  func open(_ url: URL) -> Bool

  /// Opens Finder windows that show `fileURLs` selected.
  func activateFileViewerSelecting(_ fileURLs: [URL])
}

extension NSWorkspace: Workspace {}
