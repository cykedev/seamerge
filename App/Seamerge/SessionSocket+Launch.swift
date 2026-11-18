import Foundation
import SessionIPC

extension SessionSocket {
  /// The setting that names another folder for the socket, given only when the app is launched,
  /// as `-SessionSocketDirectory <path>`: a copy that is launched to be checked listens there
  /// and leaves the socket of a running Seamerge alone.
  static let directoryArgument = "SessionSocketDirectory"

  /// The socket the app listens on with the settings it was launched with, `arguments`: in the
  /// folder that `directoryArgument` names, if one does, and the default socket otherwise.
  ///
  /// Only the launch sets the folder: a value kept in the settings of the app is never read, so
  /// that the helper, which always looks at the default socket, finds every app a person starts.
  static func url(launchedWith arguments: [String: Any]) -> URL {
    guard let directory = arguments[directoryArgument] as? String, !directory.isEmpty else {
      return defaultURL
    }
    return URL(filePath: directory, directoryHint: .isDirectory).appending(
      path: "seamerge.sock", directoryHint: .notDirectory)
  }
}
