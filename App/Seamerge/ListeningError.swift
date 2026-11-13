import Foundation
import SessionIPC

/// Why the app cannot take sessions from the command line.
enum ListeningError: LocalizedError, Equatable {
  /// Another copy of the app listens already.
  case anotherCopyIsRunning

  /// The path of the socket is longer than the system allows.
  case socketPathTooLong

  /// The folder of the socket, at the path, belongs to another user or is no folder.
  case socketFolderNotPrivate(path: String)

  /// The socket cannot be set up for another reason.
  case socketUnavailable

  /// The reason the socket of `error` gives.
  init(_ error: SessionError) {
    self =
      switch error {
      case .socketInUse: .anotherCopyIsRunning
      case .socketPathTooLong: .socketPathTooLong
      case .socketDirectoryNotPrivate(let path): .socketFolderNotPrivate(path: path)
      default: .socketUnavailable
      }
  }

  var errorDescription: String? {
    switch self {
    case .anotherCopyIsRunning:
      String(
        localized: "Another copy of Seamerge is already running.",
        comment:
          "Alert at launch: a second copy of the app cannot take merges from the command line.")
    case .socketPathTooLong, .socketFolderNotPrivate, .socketUnavailable:
      String(
        localized: "Seamerge can’t take merges from the command line.",
        comment: "Alert at launch: the app cannot listen for the command-line helper.")
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .anotherCopyIsRunning:
      String(
        localized:
          "Merges from the command line open in the other copy. Quit it, then open this one again.",
        comment: "Alert at launch: what to do when another copy runs.")
    case .socketPathTooLong:
      String(
        localized:
          "The path of its connection to the command line is longer than macOS allows. Comparing files still works. This is a bug in Seamerge; please report it.",
        comment: "Alert at launch: the path of the socket is too long; what still works.")
    case .socketFolderNotPrivate(let path):
      String(
        localized:
          "“\(path)” isn’t a folder of yours alone. Remove it, then open Seamerge again. Comparing files still works.",
        comment: "Alert at launch: the folder of the socket belongs to someone else; what to do.")
    case .socketUnavailable:
      String(
        localized:
          "Comparing files still works. Quit Seamerge and open it again to merge from the command line.",
        comment: "Alert at launch: what to do when the app cannot listen for the command line.")
    }
  }
}
