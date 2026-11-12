/// How the command-line helper starts the app, which both of them must agree on.
enum HelperLaunch {
  /// The argument the helper starts the app with: a session is on its way, so the app shows no
  /// window of its own when it starts.
  static let argument = "--for-session"
}
