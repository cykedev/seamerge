import Foundation

/// Whether session windows color their code by its syntax, kept in the user defaults for every
/// window and across launches; the code is colored until the user turns it off.
@MainActor
struct SyntaxHighlighting {
  /// Posted, with the user defaults as the object, after highlighting was turned on or off.
  static let didChangeNotification = Notification.Name(
    "app.eiden.seamerge.SyntaxHighlightingDidChange")

  private static let key = "HighlightsNoSyntax"

  /// The user defaults that keep the choice.
  let defaults: UserDefaults

  /// Whether the windows color their code.
  var isOn: Bool {
    get { !defaults.bool(forKey: Self.key) }
    nonmutating set {
      guard newValue != isOn else { return }
      defaults.set(!newValue, forKey: Self.key)
      NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
  }
}
