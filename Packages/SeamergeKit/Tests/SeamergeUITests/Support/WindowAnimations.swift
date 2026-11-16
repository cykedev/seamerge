import Foundation

/// The animations of windows in the test process.
///
/// While the screen is locked, the animation that shows a window never ends and holds a dispatch
/// thread until the process exits. Past 64 such threads, any work that waits for a thread of its
/// own waits forever, and tests hang.
@MainActor
enum WindowAnimations {
  /// The setting of AppKit that turns the animations of windows on or off.
  static let settingKey = "NSAutomaticWindowAnimationsEnabled"

  /// Whether the animations of windows are off for this process.
  static var areOff: Bool {
    arguments[settingKey] as? Bool == false
  }

  /// Turns the animations of windows off for the rest of the process.
  ///
  /// The setting goes into the argument domain, as if the process had been launched with it, so
  /// it ends with the process and never reaches the settings of the user. AppKit reads it each
  /// time a window would animate, so it holds for every window shown afterwards, also for those a
  /// test makes without a helper. Every helper that makes a window calls this before it can
  /// show the window, directly or through `Rendering.prepare(_:size:appearance:)`.
  static func turnOff() {
    guard !areOff else { return }
    arguments[settingKey] = false
  }

  /// The settings the process was launched with, and those added to them.
  static var arguments: [String: Any] {
    get { UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain) }
    set { UserDefaults.standard.setVolatileDomain(newValue, forName: UserDefaults.argumentDomain) }
  }
}
