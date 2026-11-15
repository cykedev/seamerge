/// Starts the app, or brings it to the front if it is running already.
///
/// The command opens the app before it hands over a session, so that the app shows the window in
/// front of the terminal.
public protocol AppLauncher: Sendable {
  /// Starts the app if it is not running, and brings it to the front.
  ///
  /// This may return before the app listens for sessions; the command keeps trying to connect for
  /// a while. A copy that is quitting counts as running until it has gone.
  ///
  /// - Throws: Any error that says why the app could not be opened.
  func openApp() async throws

  /// Waits until the copy of the app that runs now has quit, at most for `timeout`, and tells
  /// whether it has; at once if none runs.
  func waitUntilAppQuits(within timeout: Duration) async -> Bool
}
