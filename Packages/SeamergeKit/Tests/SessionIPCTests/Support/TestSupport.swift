import Foundation
import Testing

@testable import SessionIPC

/// Calls `body` with the URL of a socket in a new temporary directory, and removes the directory
/// afterwards.
///
/// The directory is not created: a server creates it. Paths of Unix domain sockets are limited to
/// 103 bytes, so the name is short.
func withSocketURL(_ body: (URL) async throws -> Void) async throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "seamerge-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
  defer {
    do {
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
    } catch {
      Issue.record(error, "The temporary directory \(directory.path) was not removed")
    }
  }
  try await body(directory.appending(path: "s.sock"))
}

/// A server running in a task of its own whose connections the test receives.
///
/// The handler of each connection hands it to the test and keeps it open until the tool
/// disconnects or the server stops.
struct RunningServer {
  let task: Task<Void, Never>
  private var connections: AsyncStream<SessionConnection>.Iterator

  /// Creates a server at `url` and runs it.
  init(at url: URL) throws {
    let server = try SessionServer(socketURL: url)
    let (connections, sink) = AsyncStream.makeStream(of: SessionConnection.self)
    task = Task {
      await server.run { connection in
        sink.yield(connection)
        await connection.waitUntilDisconnected()
      }
      sink.finish()
    }
    self.connections = connections.makeAsyncIterator()
  }

  /// Returns the next connection whose request reached the handler.
  mutating func nextConnection() async throws -> SessionConnection {
    try #require(await connections.next())
  }

  /// Stops the server and waits until it has stopped.
  func stop() async {
    task.cancel()
    await task.value
  }
}

/// A peer that writes and reads raw lines, for messages a well-behaved side never sends.
struct RawPeer {
  private let connection: LineConnection
  private var reader: LineReader

  private init(_ descriptor: SocketDescriptor) {
    connection = LineConnection(descriptor: descriptor)
    reader = connection.makeLineReader()
  }

  /// Connects to the server at `url` as a tool would.
  static func connect(to url: URL) throws -> RawPeer {
    let descriptor = try SocketDescriptor.makeUnixStream()
    try descriptor.connect(to: SocketAddress(path: url.path))
    return RawPeer(descriptor)
  }

  /// Listens at `url` as the app would, and returns the first tool that connects.
  static func acceptFirstConnection(at url: URL) async throws -> RawPeer {
    let listener = try SocketListener(url: url)
    defer { listener.close() }
    var connections = listener.connections.makeAsyncIterator()
    return RawPeer(try #require(await connections.next()))
  }

  /// Writes `text` as it is, without adding a line feed.
  func write(_ text: String) async throws {
    try await connection.write(Data(text.utf8))
  }

  /// Returns the next line, or `nil` once the other side has closed the connection.
  mutating func nextLine() async throws -> String? {
    try await reader.nextLine().map { String(decoding: $0, as: UTF8.self) }
  }

  /// Closes the connection.
  func close() {
    connection.close()
  }
}

/// Leaves a socket file at `url` that nothing listens on, as a server that crashed does.
func leaveAbandonedSocket(at url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let descriptor = try SocketDescriptor.makeUnixStream()
  try descriptor.bind(to: SocketAddress(path: url.path))
}

extension SessionRequest {
  /// A merge request whose files are named after `name`.
  static func sample(_ name: String = "file") -> SessionRequest {
    let directory = URL(filePath: "/repository/\(name)", directoryHint: .isDirectory)
    return .merge(
      Merge(
        base: directory.appending(path: "base"),
        local: directory.appending(path: "local"),
        remote: directory.appending(path: "remote"),
        output: directory.appending(path: name),
        context: MergeContext(
          operation: .merge,
          remote: Side(name: .reference("feature"), role: .incoming),
          local: Side(name: .reference("main"), role: .yours))))
  }
}
