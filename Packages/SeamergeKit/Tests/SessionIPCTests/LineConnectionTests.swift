import Darwin
import Foundation
import Testing

@testable import SessionIPC

@Suite(.timeLimit(.minutes(1)))
struct LineConnectionTests {
  @Test func linesArriveWithoutTheirLineFeed() async throws {
    let (writer, reader) = try makeConnectedPair()
    var lines = reader.makeLineReader()

    try await writer.write(Data("first\nsecond\n\n".utf8))

    #expect(try await lines.nextText() == "first")
    #expect(try await lines.nextText() == "second")
    #expect(try await lines.nextText() == "")
  }

  @Test func lineWrittenInPiecesArrivesWhole() async throws {
    let (writer, reader) = try makeConnectedPair()
    var lines = reader.makeLineReader()

    for piece in [#"{"ver"#, #"sion":1,"#, #""event":"opened"}"#, "\n"] {
      try await writer.write(Data(piece.utf8))
    }

    #expect(try await lines.nextText() == #"{"version":1,"event":"opened"}"#)
  }

  @Test func incompleteLineIsDiscardedWhenTheConnectionEnds() async throws {
    let (writer, reader) = try makeConnectedPair()
    var lines = reader.makeLineReader()

    try await writer.write(Data("whole\nhalf".utf8))
    writer.close()

    #expect(try await lines.nextText() == "whole")
    #expect(try await lines.nextText() == nil)
  }

  @Test func overlongLineIsRefused() async throws {
    let (writer, reader) = try makeConnectedPair()
    var lines = reader.makeLineReader()
    let overlong = Data(repeating: UInt8(ascii: "x"), count: LineReader.maximumLineLength + 1)

    // The reader stops reading at the limit, so the write must not hold up the test.
    let writing = Task { try await writer.write(overlong + Data("\n".utf8)) }
    await #expect(throws: SessionError.messageTooLong) { try await lines.nextLine() }
    reader.close()
    _ = await writing.result
  }

  @Test func lineOfTheLongestLengthIsAccepted() async throws {
    let (writer, reader) = try makeConnectedPair()
    var lines = reader.makeLineReader()
    let longest = Data(repeating: UInt8(ascii: "x"), count: LineReader.maximumLineLength)

    let writing = Task { try await writer.write(longest + Data("\n".utf8)) }

    #expect(try await lines.nextLine() == longest)
    try await writing.value
  }

  @Test func closingEndsTheLinesOnBothSides() async throws {
    let (first, second) = try makeConnectedPair()
    var firstLines = first.makeLineReader()
    var secondLines = second.makeLineReader()

    first.close()

    #expect(try await firstLines.nextLine() == nil)
    #expect(try await secondLines.nextLine() == nil)
  }

  @Test func releasingAConnectionClosesItsSocket() async throws {
    let (_, second) = try makeConnectedPair()
    var lines = second.makeLineReader()

    #expect(try await lines.nextLine() == nil)
  }

  @Test func writingAfterThePeerHasGoneFailsWithoutEndingTheProcess() async throws {
    let (first, second) = try makeConnectedPair()
    var lines = first.makeLineReader()
    second.close()
    #expect(try await lines.nextLine() == nil)

    await #expect(throws: SessionError.disconnected) {
      try await first.write(Data("anyone there?\n".utf8))
    }
  }

  @Test func writingAfterClosingFails() async throws {
    let (connection, peer) = try makeConnectedPair()

    connection.close()
    defer { peer.close() }

    await #expect(throws: SessionError.disconnected) {
      try await connection.write(Data("late\n".utf8))
    }
  }

  private func makeConnectedPair() throws -> (LineConnection, LineConnection) {
    var descriptors: [Int32] = [-1, -1]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
      throw SessionError.socketCallFailed(call: "socketpair", code: errno)
    }
    let first = try SocketDescriptor.adopting(descriptors[0])
    let second = try SocketDescriptor.adopting(descriptors[1])
    return (LineConnection(descriptor: first), LineConnection(descriptor: second))
  }
}

extension LineReader {
  fileprivate mutating func nextText() async throws -> String? {
    try await nextLine().map { String(decoding: $0, as: UTF8.self) }
  }
}
