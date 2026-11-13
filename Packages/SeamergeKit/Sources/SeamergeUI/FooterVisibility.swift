import Foundation

/// Whether session windows show their footer, kept in the user defaults for every window and
/// across launches; the footer shows until the user hides it.
@MainActor
struct FooterVisibility {
  /// Posted, with the user defaults as the object, after the footer was hidden or shown.
  static let didChangeNotification = Notification.Name(
    "app.eiden.seamerge.FooterVisibilityDidChange")

  private static let key = "HidesFooter"

  /// The user defaults that keep the choice.
  let defaults: UserDefaults

  /// Whether the windows show their footer.
  var isVisible: Bool {
    get { !defaults.bool(forKey: Self.key) }
    nonmutating set {
      guard newValue != isVisible else { return }
      defaults.set(!newValue, forKey: Self.key)
      NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }
  }
}
