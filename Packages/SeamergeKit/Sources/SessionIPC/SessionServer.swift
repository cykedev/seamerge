public import Foundation
import os

/// The side of the app: accepts the connections of command-line tools and serves each with a
/// handler of its own.
///
/// Each tool sends one request and then waits; the handler answers it with events and returns when
/// the session is over. Requests that cannot be read never reach the handler: the tool gets a
/// ``SessionEvent/rejected(_:)`` event instead.
public final class SessionServer: Sendable {
  private let listener: SocketListener

  /// Creates the socket at `socketURL` and starts accepting connections.
  ///
  /// Tools can connect as soon as this returns; their requests wait until ``run(handler:)`` is
  /// called. A socket file left behind by a server that ended without removing it is replaced.
  ///
  /// - Throws: ``SessionError/socketInUse(path:)`` if another server listens on the socket,
  ///   ``SessionError/socketPathOccupied(path:)`` if another kind of file is in its place, and
  ///   other ``SessionError`` cases if the socket cannot be set up.
  public init(socketURL: URL = SessionSocket.defaultURL) throws(SessionError) {
    self.listener = try SocketListener(url: socketURL)
  }

  /// Serves connections until the calling task is cancelled.
  ///
  /// Every connection runs its handler in a task of its own, so handlers run at the same time.
  /// When the task is cancelled, the server removes its socket, cancels the handlers and closes
  /// their connections, and returns once every handler has returned. A server runs once.
  ///
  /// - Parameter handler: Called with each connection whose request could be read. The connection
  ///   is closed when the handler returns.
  public func run(handler: @escaping @Sendable (SessionConnection) async -> Void) async {
    await withDiscardingTaskGroup { group in
      for await descriptor in listener.connections {
        group.addTask { await Self.serve(descriptor, handler: handler) }
      }
      listener.close()
    }
  }

  private static func serve(
    _ descriptor: SocketDescriptor, handler: @Sendable (SessionConnection) async -> Void
  ) async {
    let connection = LineConnection(descriptor: descriptor)
    defer { connection.close() }
    var reader = connection.makeLineReader()
    let request: SessionRequest
    do {
      guard let line = try await reader.nextLine(maximumLength: MessageCoding.maximumRequestLength)
      else {
        Logger.sessionIPC.notice("A session connection ended before its request")
        return
      }
      request = try MessageCoding.decode(SessionRequest.self, from: line)
    } catch {
      await reject(connection, because: error)
      return
    }

    let endOfInput = Task { [reader] in
      var reader = reader
      do {
        if try await reader.nextLine() != nil {
          Logger.sessionIPC.error("A session connection sent more than its request")
        }
      } catch {
        Logger.sessionIPC.error("A session connection sent an overlong message after its request")
      }
      connection.close()
    }
    let session = SessionConnection(
      request: request, connection: connection, endOfInput: endOfInput)
    await withTaskCancellationHandler {
      await handler(session)
    } onCancel: {
      connection.close()
    }
    connection.close()
    await endOfInput.value
  }

  private static func reject(_ connection: LineConnection, because error: SessionError) async {
    Logger.sessionIPC.error("Rejecting a session request: \(String(describing: error))")
    let reason: SessionRejection =
      switch error {
      case .unsupportedVersion: .unsupportedVersion
      default: .malformedRequest
      }
    do {
      try await connection.write(MessageCoding.line(for: SessionEvent.rejected(reason)))
    } catch {
      Logger.sessionIPC.notice("The rejected session connection ended before the answer")
    }
  }
}
