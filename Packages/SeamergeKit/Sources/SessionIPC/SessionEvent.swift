/// A message from the app to the command-line tool about the request it sent.
public enum SessionEvent: Sendable, Hashable {
  /// The app shows the window for the request.
  case opened

  /// The window was closed; the session is over.
  case closed(SessionOutcome)

  /// The app refused the request without opening a window.
  case rejected(SessionRejection)
}

/// How the user ended a session.
public enum SessionOutcome: String, Sendable, Hashable, Codable {
  /// The result was saved.
  case saved

  /// The window was closed without saving.
  case cancelled

  /// The exit status the command-line tool ends with, so that Git sees whether the merge was
  /// resolved.
  public var exitStatus: Int32 {
    switch self {
    case .saved: 0
    case .cancelled: 1
    }
  }
}

/// Why the app refused a request.
public enum SessionRejection: String, Sendable, Hashable, Codable {
  /// The request was written in another version of the protocol.
  case unsupportedVersion

  /// The request could not be read.
  case malformedRequest

  /// The app read the request but cannot open a window of its kind.
  case unsupportedRequest
}

extension SessionEvent: Codable {
  private enum CodingKeys: String, CodingKey {
    case version, event, outcome, exit, reason
  }

  private enum Name: String, Codable {
    case opened, closed, rejected
  }

  /// Decodes an event, refusing one of another protocol version before reading anything else.
  ///
  /// - Throws: ``SessionError/unsupportedVersion(_:)`` for another version, `DecodingError` for
  ///   anything else that is wrong, including an exit status that does not match the outcome.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try MessageCoding.checkVersion(in: container, forKey: .version)
    switch try container.decode(Name.self, forKey: .event) {
    case .opened:
      self = .opened
    case .closed:
      let outcome = try container.decode(SessionOutcome.self, forKey: .outcome)
      guard try container.decode(Int32.self, forKey: .exit) == outcome.exitStatus else {
        throw DecodingError.dataCorruptedError(
          forKey: .exit, in: container,
          debugDescription: "The exit status does not match the outcome \(outcome.rawValue).")
      }
      self = .closed(outcome)
    case .rejected:
      self = .rejected(try container.decode(SessionRejection.self, forKey: .reason))
    }
  }

  /// Encodes the event together with the protocol version.
  ///
  /// A closed session carries its exit status next to its outcome, so that the message tells a
  /// reader of the protocol what the command-line tool ends with.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(MessageCoding.version, forKey: .version)
    switch self {
    case .opened:
      try container.encode(Name.opened, forKey: .event)
    case .closed(let outcome):
      try container.encode(Name.closed, forKey: .event)
      try container.encode(outcome, forKey: .outcome)
      try container.encode(outcome.exitStatus, forKey: .exit)
    case .rejected(let reason):
      try container.encode(Name.rejected, forKey: .event)
      try container.encode(reason, forKey: .reason)
    }
  }
}
