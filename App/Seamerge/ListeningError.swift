import Foundation
import SessionIPC

/// Why the app cannot take sessions from Git.
enum ListeningError: LocalizedError, Equatable {
  /// Another copy of the app listens already.
  case anotherCopyIsRunning

  /// The socket cannot be set up.
  case socketUnavailable

  /// The reason the socket of `error` gives.
  init(_ error: SessionError) {
    self =
      switch error {
      case .socketInUse: .anotherCopyIsRunning
      default: .socketUnavailable
      }
  }

  var errorDescription: String? {
    switch self {
    case .anotherCopyIsRunning:
      String(
        localized: "Another copy of Seamerge is already running.",
        comment: "Alert at launch: a second copy of the app cannot take merges from Git.")
    case .socketUnavailable:
      String(
        localized: "Seamerge can’t take merges from Git.",
        comment: "Alert at launch: the app cannot listen for the command-line helper.")
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .anotherCopyIsRunning:
      String(
        localized: "Git opens merges in the other copy. Quit it, then open this one again.",
        comment: "Alert at launch: what to do when another copy runs.")
    case .socketUnavailable:
      String(
        localized:
          "Comparing files still works. Quit Seamerge and open it again to use it with Git.",
        comment: "Alert at launch: what to do when the app cannot listen for Git.")
    }
  }
}
