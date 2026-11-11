/// Starts the app, or brings it to the front if it is running already.
///
/// The command opens the app before it hands over a session, so that the app shows the window in
/// front of the terminal.
public protocol AppLauncher: Sendable {
  /// Starts the app if it is not running, and brings it to the front.
  ///
  /// This may return before the app listens for sessions; the command keeps trying to connect for
  /// a while.
  ///
  /// - Throws: Any error that says why the app could not be opened.
  func openApp() async throws
}
