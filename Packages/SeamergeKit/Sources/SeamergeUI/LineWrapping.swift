import Foundation

/// Whether session windows wrap long lines at the width of their panes, kept in the user
/// defaults for every window and across launches; lines run on until the user turns it on.
@MainActor
struct LineWrapping {
  /// Posted, with the user defaults as the object, after wrapping was turned on or off.
  static let didChangeNotification = Notification.Name(
    "app.eiden.seamerge.LineWrappingDidChange")

  private static let key = "WrapsLines"

  /// The user defaults that keep the choice.
  let defaults: UserDefaults

  /// Whether the windows wrap long lines.
  var isOn: Bool {
    get { defaults.bool(forKey: Self.key) }
    nonmutating set {
      guard newValue != isOn else { return }
      defaults.set(newValue, forKey: Self.key)
      NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
  }
}
