import Foundation
import SessionIPC
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SocketFileTests {
  @Test func abandonedSocketFileIsReplaced() async throws {
    try await withSocketURL { url in
      try leaveAbandonedSocket(at: url)
      #expect(FileManager.default.fileExists(atPath: url.path))

      var server = try RunningServer(at: url)
      async let outcome = SessionClient(socketURL: url).perform(.sample())
      try await server.nextConnection().send(.closed(.saved))

      #expect(try await outcome == .saved)
      await server.stop()
    }
  }

  @Test func socketOfARunningServerIsNotTakenOver() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)

      #expect(throws: SessionError.socketInUse(path: url.path)) {
        try SessionServer(socketURL: url)
      }

      async let outcome = SessionClient(socketURL: url).perform(.sample())
      try await server.nextConnection().send(.closed(.cancelled))
      #expect(try await outcome == .cancelled)
      await server.stop()
    }
  }

  @Test func otherFileInThePlaceOfTheSocketIsLeftAlone() async throws {
    try await withSocketURL { url in
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("keep me".utf8).write(to: url)

      #expect(throws: SessionError.socketPathOccupied(path: url.path)) {
        try SessionServer(socketURL: url)
      }
      #expect(try Data(contentsOf: url) == Data("keep me".utf8))
    }
  }

  @Test func socketIsOpenOnlyToTheUser() async throws {
    try await withSocketURL { url in
      let server = try RunningServer(at: url)

      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      #expect(attributes[.type] as? FileAttributeType == .typeSocket)
      #expect(attributes[.posixPermissions] as? Int == 0o600)
      await server.stop()
    }
  }

  @Test func stoppedServerRemovesItsSocket() async throws {
    try await withSocketURL { url in
      let server = try RunningServer(at: url)

      await server.stop()

      #expect(!FileManager.default.fileExists(atPath: url.path))
      await #expect(throws: SessionError.serverUnreachable(path: url.path)) {
        try await SessionClient(socketURL: url, connectionTimeout: .zero).perform(.sample())
      }
    }
  }

  @Test func stoppedServerLeavesTheSocketOfItsSuccessorAlone() async throws {
    try await withSocketURL { url in
      let predecessor = try RunningServer(at: url)
      try FileManager.default.removeItem(at: url)
      var successor = try RunningServer(at: url)

      await predecessor.stop()

      async let outcome = SessionClient(socketURL: url).perform(.sample())
      try await successor.nextConnection().send(.closed(.saved))
      #expect(try await outcome == .saved)
      await successor.stop()
    }
  }

  @Test func toolWaitsForTheServerToStart() async throws {
    try await withSocketURL { url in
      async let outcome = SessionClient(socketURL: url).perform(.sample())

      var server = try RunningServer(at: url)
      try await server.nextConnection().send(.closed(.saved))

      #expect(try await outcome == .saved)
      await server.stop()
    }
  }

  @Test func toolGivesUpWhenNoSocketAppears() async throws {
    try await withSocketURL { url in
      let client = SessionClient(socketURL: url, connectionTimeout: .milliseconds(250))

      await #expect(throws: SessionError.serverUnreachable(path: url.path)) {
        try await client.perform(.sample())
      }
    }
  }

  @Test func toolGivesUpWhenNothingListensOnTheSocket() async throws {
    try await withSocketURL { url in
      try leaveAbandonedSocket(at: url)
      let client = SessionClient(socketURL: url, connectionTimeout: .milliseconds(250))

      await #expect(throws: SessionError.serverUnreachable(path: url.path)) {
        try await client.perform(.sample())
      }
    }
  }

  @Test func overlongSocketPathIsRefused() async {
    let url = URL(filePath: "/tmp/" + String(repeating: "x", count: 100))

    #expect(throws: SessionError.socketPathTooLong(path: url.path)) {
      try SessionServer(socketURL: url)
    }
    await #expect(throws: SessionError.socketPathTooLong(path: url.path)) {
      try await SessionClient(socketURL: url).perform(.sample())
    }
  }

  @Test func defaultSocketIsInTheFolderOfTheAppInApplicationSupport() {
    #expect(
      SessionSocket.defaultURL.path(percentEncoded: false).hasSuffix(
        "/Library/Application Support/Seamerge/seamerge.sock"))
  }
}
