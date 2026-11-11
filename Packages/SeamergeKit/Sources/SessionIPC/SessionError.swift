/// An error in the exchange between the command-line tool and the app.
public enum SessionError: Error, Sendable, Hashable {
  /// The path of the socket is longer than a Unix domain socket allows.
  case socketPathTooLong(path: String)

  /// The directory for the socket could not be created.
  case socketDirectoryUnavailable(path: String, reason: String)

  /// Another server listens on the socket.
  case socketInUse(path: String)

  /// Something other than a socket is in the place of the socket, and it is left alone.
  case socketPathOccupied(path: String)

  /// A system call on a socket failed.
  ///
  /// - Parameters:
  ///   - call: The name of the system call, such as `bind`.
  ///   - code: The value of `errno` after the call.
  case socketCallFailed(call: String, code: Int32)

  /// No server accepted a connection within the time limit.
  case serverUnreachable(path: String)

  /// The other side closed the connection before the session ended.
  case disconnected

  /// The task waiting for the session was cancelled.
  case cancelled

  /// A message was written in another version of the protocol.
  case unsupportedVersion(Int)

  /// A message could not be read; the associated text says why.
  case malformedMessage(String)

  /// A message did not end within the longest length a message may have.
  case messageTooLong

  /// The app refused the request.
  case rejected(SessionRejection)
}
