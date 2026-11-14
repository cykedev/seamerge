import Foundation
import SessionIPC
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SessionTests {
  @Test func requestAndEventsMakeTheRoundTrip() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      async let outcome = client.perform(.sample())

      let connection = try await server.nextConnection()
      #expect(connection.request == .sample())
      try await connection.send(.opened)
      try await connection.send(.closed(.saved))

      #expect(try await outcome == .closed(.saved))
      await server.stop()
    }
  }

  @Test func twoConnectionsAreServedAtTheSameTime() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      async let first = client.perform(.sample("first"))
      async let second = client.perform(.sample("second"))

      // Both handlers are running before either session ends.
      let connections = [try await server.nextConnection(), try await server.nextConnection()]
      for connection in connections {
        let isFirst = connection.request == .sample("first")
        try await connection.send(.closed(isFirst ? .saved : .cancelled))
      }

      #expect(Set(connections.map(\.request)) == [.sample("first"), .sample("second")])
      #expect(try await first == .closed(.saved))
      #expect(try await second == .closed(.cancelled))
      await server.stop()
    }
  }

  @Test func toolThatStopsWaitingIsReportedToTheHandler() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let tool = Task { try await SessionClient(socketURL: url).perform(.sample()) }
      let connection = try await server.nextConnection()
      try await connection.send(.opened)

      tool.cancel()

      await connection.waitUntilDisconnected()
      await #expect(throws: SessionError.cancelled) { try await tool.value }
      await #expect(throws: SessionError.disconnected) {
        try await connection.send(.closed(.saved))
      }
      await server.stop()
    }
  }

  @Test func stoppingTheServerDisconnectsTheTool() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      let tool = Task { try await client.perform(.sample()) }
      let connection = try await server.nextConnection()
      try await connection.send(.opened)

      await server.stop()

      await #expect(throws: SessionError.disconnected) { try await tool.value }
    }
  }

  @Test func handlerThatReturnsWithoutClosingDisconnectsTheTool() async throws {
    try await withSocketURL { url in
      let server = try SessionServer(socketURL: url)
      let running = Task { await server.run { _ in } }

      await #expect(throws: SessionError.disconnected) {
        try await SessionClient(socketURL: url).perform(.sample())
      }
      running.cancel()
      await running.value
    }
  }

  @Test func requestOfAnotherVersionIsRejectedWithoutReachingTheHandler() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      var tool = try RawPeer.connect(to: url)

      try await tool.write(#"{"version":1,"anything":"old"}"# + "\n")

      #expect(
        try await tool.nextLine()
          == #"{"event":"rejected","reason":"unsupportedVersion","version":2}"#)
      #expect(try await tool.nextLine() == nil)
      try await expectNextRequestComesFromAWellBehavedTool(server: &server, url: url)
      await server.stop()
    }
  }

  @Test func unreadableRequestIsRejectedWithoutReachingTheHandler() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      var tool = try RawPeer.connect(to: url)

      try await tool.write("merge, please\n")

      #expect(
        try await tool.nextLine()
          == #"{"event":"rejected","reason":"malformedRequest","version":2}"#)
      #expect(try await tool.nextLine() == nil)
      try await expectNextRequestComesFromAWellBehavedTool(server: &server, url: url)
      await server.stop()
    }
  }

  @Test func requestWrittenInPiecesReachesTheHandler() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let tool = try RawPeer.connect(to: url)
      let line = try String(decoding: JSONEncoder().encode(SessionRequest.sample()), as: UTF8.self)

      let middle = line.index(line.startIndex, offsetBy: line.count / 2)
      try await tool.write(String(line[..<middle]))
      try await tool.write(String(line[middle...]) + "\n")

      #expect(try await server.nextConnection().request == .sample())
      tool.close()
      await server.stop()
    }
  }

  @Test func toolThatLeavesInTheMiddleOfItsRequestNeverReachesTheHandler() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let tool = try RawPeer.connect(to: url)

      try await tool.write(#"{"version":2,"merge":{"base":"/rep"#)
      tool.close()

      try await expectNextRequestComesFromAWellBehavedTool(server: &server, url: url)
      await server.stop()
    }
  }

  @Test func toolThatSendsMoreThanItsRequestIsDisconnected() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      var tool = try RawPeer.connect(to: url)
      let request = try String(
        decoding: JSONEncoder().encode(SessionRequest.sample()), as: UTF8.self)

      try await tool.write(request + "\n" + request + "\n")

      let connection = try await server.nextConnection()
      await connection.waitUntilDisconnected()
      #expect(try await tool.nextLine() == nil)
      await server.stop()
    }
  }

  @Test func eventOfAnotherVersionFailsTheTool() async throws {
    try await withSocketURL { url in
      let tool = Task { try await SessionClient(socketURL: url).perform(.sample()) }
      var app = try await RawPeer.acceptFirstConnection(at: url)
      #expect(try await app.nextLine() != nil)

      try await app.write(#"{"event":"opened","version":1}"# + "\n")

      await #expect(throws: SessionError.unsupportedVersion(1)) { try await tool.value }
    }
  }

  @Test func rejectionFailsTheTool() async throws {
    try await withSocketURL { url in
      let tool = Task { try await SessionClient(socketURL: url).perform(.sample()) }
      var app = try await RawPeer.acceptFirstConnection(at: url)
      #expect(try await app.nextLine() != nil)

      try await app.write(#"{"event":"rejected","reason":"malformedRequest","version":2}"# + "\n")

      await #expect(throws: SessionError.rejected(.malformedRequest)) { try await tool.value }
    }
  }

  @Test func appThatLeavesInTheMiddleOfAnEventDisconnectsTheTool() async throws {
    try await withSocketURL { url in
      let tool = Task { try await SessionClient(socketURL: url).perform(.sample()) }
      var app = try await RawPeer.acceptFirstConnection(at: url)
      #expect(try await app.nextLine() != nil)

      try await app.write(#"{"event":"closed","exit":0,"outc"#)
      app.close()

      await #expect(throws: SessionError.disconnected) { try await tool.value }
    }
  }

  /// Expects the next connection that reaches the handler to be a well-behaved tool's, which
  /// shows that nothing a misbehaving tool sent before reached it and that the server still works.
  private func expectNextRequestComesFromAWellBehavedTool(
    server: inout RunningServer, url: URL
  ) async throws {
    async let outcome = SessionClient(socketURL: url).perform(.sample("well-behaved"))
    let connection = try await server.nextConnection()
    #expect(connection.request == .sample("well-behaved"))
    try await connection.send(.closed(.saved))
    #expect(try await outcome == .closed(.saved))
  }
}
