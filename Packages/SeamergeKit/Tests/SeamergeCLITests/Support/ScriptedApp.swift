import Foundation
import SessionIPC
import Testing

/// A server in the test that stands in for the app and ends each session as the test says.
struct ScriptedApp {
  /// How the app in the test ends a session.
  enum Ending: Sendable {
    /// Closes the window with this outcome.
    case close(SessionOutcome)

    /// Writes the text into the output of the merge, then closes the window as saved.
    case save(String)

    /// Goes away without closing the window, as an app that crashes.
    case disconnect

    /// Takes over the files of a collected comparison without a window.
    case accept

    /// Refuses the request without opening a window.
    case reject(SessionRejection)
  }

  private let task: Task<Void, Never>
  private var requests: AsyncStream<SessionRequest>.Iterator

  /// Creates a server at `url` that ends every session with `ending`.
  init(at url: URL, ending: Ending) throws {
    try self.init(at: url) { _ in ending }
  }

  /// Creates a server at `url` that asks `ending` how to end each session.
  init(at url: URL, ending: @escaping @Sendable (SessionRequest) -> Ending) throws {
    let server = try SessionServer(socketURL: url)
    let (requests, sink) = AsyncStream.makeStream(of: SessionRequest.self)
    task = Task {
      await server.run { connection in
        sink.yield(connection.request)
        do {
          let ending = ending(connection.request)
          if case .reject(let reason) = ending {
            try await connection.send(.rejected(reason))
            return
          }
          if case .accept = ending {
            try await connection.send(.accepted)
            return
          }
          try await connection.send(.opened)
          switch ending {
          case .close(let outcome):
            try await connection.send(.closed(outcome))
          case .save(let text):
            guard case .merge(let merge) = connection.request else {
              Issue.record("Only a merge can be saved")
              return
            }
            try Data(text.utf8).write(to: merge.output)
            try await connection.send(.closed(.saved))
          case .disconnect, .reject, .accept:
            return
          }
        } catch {
          Issue.record(error, "The app in the test could not end the session")
        }
        await connection.waitUntilDisconnected()
      }
      sink.finish()
    }
    self.requests = requests.makeAsyncIterator()
  }

  /// Returns the request of the next session.
  mutating func nextRequest() async throws -> SessionRequest {
    try #require(await requests.next())
  }

  /// Stops the server and waits until it has stopped.
  func stop() async {
    task.cancel()
    await task.value
  }
}
