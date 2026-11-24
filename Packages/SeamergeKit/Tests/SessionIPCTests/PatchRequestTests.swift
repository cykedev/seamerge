import Foundation
import Testing

@testable import SessionIPC

@Suite(.timeLimit(.minutes(1)))
struct PatchRequestTests {
  @Test func patchSurvivesEncodingAndDecodingWithItsBytes() throws {
    var text = Data("--- a\n+++ b\n@@ -1 +1 @@\n-gr".utf8)
    text.append(contentsOf: [0xF6, 0xDF, 0x0A, 0x00, 0xFF])
    for request in [
      SessionRequest.patch(.init(text: text, fileName: "change.patch", waitsForWindow: true)),
      .patch(.init(text: Data())),
    ] {
      #expect(try roundTrip(request) == request)
    }
  }

  @Test(arguments: [SessionRejection.unreadablePatch, .windowNotOpened])
  func refusalOfAPatchSurvivesEncodingAndDecoding(reason: SessionRejection) throws {
    #expect(try roundTrip(SessionEvent.rejected(reason)) == .rejected(reason))
  }

  /// The largest patch fits into a request in Base64 with room to spare for the rest of the
  /// message.
  @Test func largestPatchFitsIntoTheLongestRequest() {
    let base64Length = (SessionRequest.Patch.maximumByteCount + 2) / 3 * 4
    #expect(base64Length + 1_024 < MessageCoding.maximumRequestLength)
  }

  @Test func requestWithoutWaitSaysNothingAboutIt() throws {
    let json = try json(SessionRequest.patch(.init(text: Data("x".utf8))))

    #expect(json == #"{"patch":{"text":"eA=="},"version":2}"#)
  }

  @Test func requestThatNamesTwoKindsCannotBeDecoded() {
    let line = #"{"version":2,"patch":{"text":""},"folders":{"left":"/a","right":"/b"}}"#

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SessionRequest.self, from: Data(line.utf8))
    }
  }

  @Test func toolThatDoesNotWaitEndsOnceTheWindowShows() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      async let reply = client.perform(.patch(.init(text: Data("x".utf8))))

      let connection = try await server.nextConnection()
      try await connection.send(.opened)

      #expect(try await reply == .accepted)
      await connection.waitUntilDisconnected()
      await server.stop()
    }
  }

  @Test func toolThatWaitsEndsOnceTheWindowCloses() async throws {
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      async let reply = client.perform(
        .patch(.init(text: Data("x".utf8), waitsForWindow: true)))

      let connection = try await server.nextConnection()
      try await connection.send(.opened)
      try await connection.send(.closed(.saved))

      #expect(try await reply == .closed(.saved))
      await server.stop()
    }
  }

  @Test func patchOfManyMegabytesReachesTheApp() async throws {
    let line = Data("+a line that the patch adds to the file\n".utf8)
    var text = Data()
    while text.count < 24 << 20 {
      text.append(line)
    }
    try await withSocketURL { url in
      var server = try RunningServer(at: url)
      let client = SessionClient(socketURL: url)
      let request = SessionRequest.patch(.init(text: text, fileName: "large.patch"))
      async let reply = client.perform(request)

      let connection = try await server.nextConnection()
      #expect(connection.request == request)
      try await connection.send(.opened)

      #expect(try await reply == .accepted)
      await server.stop()
    }
  }

  private func roundTrip<Message: Codable>(_ message: Message) throws -> Message {
    try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
  }

  private func json(_ message: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(message), as: UTF8.self)
  }
}
