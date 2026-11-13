/// The language chosen for each file, by its path, kept while the app runs and forgotten when
/// it quits.
///
/// The windows of the app share ``shared``, so that every window of the same file finds the
/// choice of the one before.
@MainActor
final class SyntaxChoices {
  /// The choices of the app, which every window it opens shares.
  static let shared = SyntaxChoices()

  private var choices: [String: SyntaxChoice] = [:]

  /// The choice for the file at `path`; Automatic until another is chosen.
  subscript(path: String) -> SyntaxChoice {
    get { choices[path] ?? .automatic }
    set { choices[path] = newValue == .automatic ? nil : newValue }
  }
}
