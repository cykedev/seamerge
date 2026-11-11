import Foundation
import SessionIPC
import Testing

struct MessageTests {
  @Test func mergeRequestSurvivesEncodingAndDecoding() throws {
    let request = SessionRequest.merge(
      .init(
        base: URL(filePath: "/tmp/base 1"),
        local: URL(filePath: "/tmp/ä/local"),
        remote: URL(filePath: "/tmp/%20/remote"),
        output: URL(filePath: "/repository/file.txt"),
        context: .init(
          operation: .rebase,
          remote: .init(
            name: .commit(abbreviatedHash: "1a2b3c4", subject: "Fix it", branch: "feature"),
            role: .yourCommit,
            commit: .init(
              abbreviatedHash: "1a2b3c4", subject: "Fix it", authorName: "Ada",
              authorDate: Date(timeIntervalSince1970: 1_700_000_000))),
          local: .init(name: .reference("main"), role: .rebaseTarget),
          base: .init(name: .stash),
          rebaseProgress: .init(targetName: .reference("main"), commitNumber: 2, commitCount: 3),
          remainingConflictedFileCount: 4)))

    #expect(try roundTrip(request) == request)
  }

  @Test func mergeWithoutBaseOrContextSurvivesEncodingAndDecoding() throws {
    let request = SessionRequest.merge(
      .init(
        base: nil, local: URL(filePath: "/l"), remote: URL(filePath: "/r"),
        output: URL(filePath: "/o")))

    #expect(try roundTrip(request) == request)
  }

  @Test func diffRequestSurvivesEncodingAndDecoding() throws {
    let request = SessionRequest.diff(
      .init(
        left: URL(filePath: "/tmp/left"),
        right: URL(filePath: "/dev/null"),
        displayPath: "Sources/a b.swift",
        leftLabel: "HEAD",
        rightLabel: "working copy",
        context: .init(
          leftRole: .before, rightRole: .workingCopy,
          filePosition: .init(number: 3, count: 12))))

    #expect(try roundTrip(request) == request)
  }

  @Test(arguments: [
    SessionEvent.opened, .closed(.saved), .closed(.cancelled), .rejected(.unsupportedVersion),
    .rejected(.malformedRequest),
  ])
  func eventSurvivesEncodingAndDecoding(_ event: SessionEvent) throws {
    #expect(try roundTrip(event) == event)
  }

  @Test func eventsAreWrittenAsTheProtocolDescribesThem() throws {
    #expect(try json(SessionEvent.opened) == #"{"event":"opened","version":1}"#)
    #expect(
      try json(SessionEvent.closed(.saved))
        == #"{"event":"closed","exit":0,"outcome":"saved","version":1}"#)
    #expect(
      try json(SessionEvent.closed(.cancelled))
        == #"{"event":"closed","exit":1,"outcome":"cancelled","version":1}"#)
  }

  @Test func requestIsWrittenWithPlainPathsAndNamedFields() throws {
    let request = SessionRequest.merge(
      .init(
        base: nil, local: URL(filePath: "/a b/ä"), remote: URL(filePath: "/r"),
        output: URL(filePath: "/o"),
        context: .init(
          remote: .init(
            name: .reference("feature"), role: .incoming,
            commit: .init(
              abbreviatedHash: "1a2b3c4", subject: "Add", authorName: "Ada",
              authorDate: Date(timeIntervalSince1970: 0))),
          base: .init(name: .stash))))

    #expect(
      try json(request)
        == #"{"merge":{"context":{"base":{"name":{"stash":{}}},"local":{},"#
        + #""remote":{"commit":{"abbreviatedHash":"1a2b3c4","authorDate":"1970-01-01T00:00:00Z","#
        + #""authorName":"Ada","subject":"Add"},"name":{"reference":{"name":"feature"}},"#
        + #""role":"incoming"}},"local":"/a b/ä","output":"/o","remote":"/r"},"version":1}"#)
  }

  @Test func commitDateIsWrittenInISO8601WhateverTheEncoderSays() throws {
    let commit = SessionRequest.Commit(
      abbreviatedHash: "1", subject: "s", authorName: "a",
      authorDate: Date(timeIntervalSince1970: 1_700_000_000))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970

    let text = String(decoding: try encoder.encode(commit), as: UTF8.self)

    #expect(text.contains(#""authorDate":"2023-11-14T22:13:20Z""#))
  }

  @Test func eventOfAnotherVersionIsRefused() {
    #expect(throws: SessionError.unsupportedVersion(2)) {
      try decode(SessionEvent.self, from: #"{"event":"opened","version":2}"#)
    }
  }

  @Test func versionIsCheckedBeforeTheContent() {
    #expect(throws: SessionError.unsupportedVersion(0)) {
      try decode(SessionRequest.self, from: #"{"version":0}"#)
    }
  }

  @Test func messageWithoutVersionIsRefused() {
    #expect(throws: DecodingError.self) {
      try decode(SessionEvent.self, from: #"{"event":"opened"}"#)
    }
  }

  @Test func exitStatusThatContradictsTheOutcomeIsRefused() {
    #expect(throws: DecodingError.self) {
      try decode(
        SessionEvent.self, from: #"{"event":"closed","exit":0,"outcome":"cancelled","version":1}"#)
    }
  }

  @Test func relativePathIsRefused() {
    #expect(throws: DecodingError.self) {
      try decode(
        SessionRequest.self,
        from: #"{"diff":{"context":{"leftRole":"before","rightRole":"after"},"left":"a","#
          + #""right":"/b"},"version":1}"#)
    }
  }

  @Test(arguments: [
    #"{"version":1}"#,
    #"{"diff":{"context":{"leftRole":"before","rightRole":"after"},"left":"/a","right":"/b"},"#
      + #""merge":{"context":{"base":{},"local":{},"remote":{}},"local":"/l","output":"/o","#
      + #""remote":"/r"},"version":1}"#,
  ])
  func requestWithoutExactlyOneOperationIsRefused(_ json: String) {
    #expect(throws: DecodingError.self) { try decode(SessionRequest.self, from: json) }
  }

  private func roundTrip<Message: Codable>(_ message: Message) throws -> Message {
    try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
  }

  private func json(_ message: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(message), as: UTF8.self)
  }

  @discardableResult
  private func decode<Message: Decodable>(_ type: Message.Type, from json: String) throws -> Message
  {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }
}
