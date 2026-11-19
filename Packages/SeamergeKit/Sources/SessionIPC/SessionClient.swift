public import Foundation
import os

/// The side of the command-line tool: hands a request to the app and waits for its outcome.
public struct SessionClient: Sendable {
  /// How long the client waits between two attempts to connect.
  private static let retryInterval = Duration.milliseconds(100)

  /// The socket the app listens on.
  public var socketURL: URL

  /// How long the client keeps trying to connect, for example while the app is starting.
  public var connectionTimeout: Duration

  /// Creates a client for the app listening on `socketURL`.
  public init(
    socketURL: URL = SessionSocket.defaultURL, connectionTimeout: Duration = .seconds(10)
  ) {
    self.socketURL = socketURL
    self.connectionTimeout = connectionTimeout
  }

  /// Sends `request` to the app and returns how the session ended.
  ///
  /// The client connects, retrying until ``connectionTimeout`` has passed while there is no
  /// socket or nothing listens on it, sends the request, and waits for the window to close, or
  /// only until the app has taken over the files of a comparison with an origin.
  /// Cancelling the calling task closes the connection; the app sees that the tool is gone.
  ///
  /// - Throws: ``SessionError/serverUnreachable(path:)`` if no server accepted the connection in
  ///   time, ``SessionError/disconnected`` if the app closed the connection before the session
  ///   ended, ``SessionError/rejected(_:)`` if the app refused the request,
  ///   ``SessionError/cancelled`` if the task was cancelled, and other ``SessionError`` cases if
  ///   the socket or a message is broken.
  public func perform(_ request: SessionRequest) async throws(SessionError) -> SessionReply {
    let connection = try await connect()
    defer { connection.close() }
    try await connection.write(MessageCoding.line(for: request))
    var reader = connection.makeLineReader()
    while let line = try await reader.nextLine() {
      switch try MessageCoding.decode(SessionEvent.self, from: line) {
      case .opened: Logger.sessionIPC.info("The app opened the session")
      case .accepted: return .accepted
      case .closed(let outcome): return .closed(outcome)
      case .rejected(let reason): throw .rejected(reason)
      }
    }
    throw Task.isCancelled ? .cancelled : .disconnected
  }

  private func connect() async throws(SessionError) -> LineConnection {
    let address = try SocketAddress(path: socketURL.path(percentEncoded: false))
    let clock = ContinuousClock()
    let deadline = clock.now + connectionTimeout
    while true {
      let descriptor = try SocketDescriptor.makeUnixStream()
      do {
        try descriptor.connect(to: address)
        return LineConnection(descriptor: descriptor)
      } catch .socketCallFailed(_, let code) where code == ENOENT || code == ECONNREFUSED {
        guard clock.now < deadline else { throw .serverUnreachable(path: address.path) }
      }
      // The app creates the socket some time after it was launched, and nothing announces that
      // moment to another process, so the client asks again until it is there.
      do {
        try await clock.sleep(until: min(clock.now + Self.retryInterval, deadline))
      } catch {
        throw .cancelled
      }
    }
  }
}
