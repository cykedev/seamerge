import Darwin
import os

/// An open socket that is closed when the last reference to it goes away.
///
/// Holding the descriptor in a reference ties its lifetime to the references: a Dispatch source or
/// channel that works on the descriptor keeps one until its cleanup has run, so the descriptor is
/// never closed while Dispatch still uses it, and never closed twice.
final class SocketDescriptor: Sendable {
  /// The descriptor; valid as long as this object exists.
  let rawValue: Int32

  private init(rawValue: Int32) {
    self.rawValue = rawValue
  }

  deinit {
    if close(rawValue) != 0 {
      Logger.sessionIPC.error("Closing socket \(self.rawValue) failed: errno \(errno)")
    }
  }

  /// Opens a new stream socket in the Unix domain.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` if the socket cannot be opened.
  static func makeUnixStream() throws(SessionError) -> SocketDescriptor {
    let rawValue = socket(AF_UNIX, SOCK_STREAM, 0)
    guard rawValue >= 0 else { throw .socketCallFailed(call: "socket", code: errno) }
    return try adopting(rawValue)
  }

  /// Takes ownership of an open socket and prepares it for use.
  ///
  /// The socket is closed in child processes, and writing to it after the other side has closed
  /// fails with `EPIPE` instead of ending the process with `SIGPIPE`. If preparing fails, the
  /// socket is closed.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` if the socket cannot be prepared.
  static func adopting(_ rawValue: Int32) throws(SessionError) -> SocketDescriptor {
    let descriptor = SocketDescriptor(rawValue: rawValue)
    guard fcntl(rawValue, F_SETFD, FD_CLOEXEC) == 0 else {
      throw .socketCallFailed(call: "fcntl", code: errno)
    }
    var enabled: Int32 = 1
    let optionSize = socklen_t(MemoryLayout.size(ofValue: enabled))
    guard setsockopt(rawValue, SOL_SOCKET, SO_NOSIGPIPE, &enabled, optionSize) == 0 else {
      throw .socketCallFailed(call: "setsockopt", code: errno)
    }
    return descriptor
  }

  /// Connects the socket to the socket at `address`.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` with `ENOENT` if there is no socket
  ///   file and with `ECONNREFUSED` if nothing listens on it.
  func connect(to address: SocketAddress) throws(SessionError) {
    let result = address.withSocketAddress { Darwin.connect(rawValue, $0, $1) }
    guard result == 0 else { throw .socketCallFailed(call: "connect", code: errno) }
  }

  /// Binds the socket to `address`, which creates the socket file.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` if the file cannot be created.
  func bind(to address: SocketAddress) throws(SessionError) {
    let result = address.withSocketAddress { Darwin.bind(rawValue, $0, $1) }
    guard result == 0 else { throw .socketCallFailed(call: "bind", code: errno) }
  }

  /// Lets the socket accept connections without waiting for them.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` if the socket cannot listen.
  func listen() throws(SessionError) {
    let flags = fcntl(rawValue, F_GETFL)
    guard flags >= 0, fcntl(rawValue, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw .socketCallFailed(call: "fcntl", code: errno)
    }
    guard Darwin.listen(rawValue, SOMAXCONN) == 0 else {
      throw .socketCallFailed(call: "listen", code: errno)
    }
  }

  /// Accepts a waiting connection, or returns `nil` if none is waiting.
  ///
  /// - Throws: ``SessionError/socketCallFailed(call:code:)`` if accepting fails for another reason.
  func accept() throws(SessionError) -> SocketDescriptor? {
    let connection = Darwin.accept(rawValue, nil, nil)
    guard connection >= 0 else {
      switch errno {
      case EAGAIN, ECONNABORTED: return nil
      case let code: throw .socketCallFailed(call: "accept", code: code)
      }
    }
    return try Self.adopting(connection)
  }
}
