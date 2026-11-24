/// A message from the app to the command-line tool about the request it sent.
public enum SessionEvent: Sendable, Hashable {
  /// The app shows the window for the request.
  case opened

  /// The app has taken over the files of a comparison that joins a window of its origin, and
  /// shows them without anyone waiting for the window.
  case accepted

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

/// How a session ended for the command-line tool: the app took over the files, or the user closed
/// the window.
public enum SessionReply: Sendable, Hashable {
  /// The app took over the files of a comparison, or showed a patch, without keeping anyone
  /// waiting for the window.
  case accepted

  /// The user closed the window.
  case closed(SessionOutcome)

  /// The exit status the command-line tool ends with: 0 for files the app took over, else that
  /// of the outcome.
  public var exitStatus: Int32 {
    switch self {
    case .accepted: 0
    case .closed(let outcome): outcome.exitStatus
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

  /// The app is quitting and opens no more windows; once it has quit, a new copy can.
  case quitting

  /// The app cannot read the patch of the request as a unified diff.
  case unreadablePatch

  /// The app read the patch but could not open its window, for a reason that it shows itself.
  case windowNotOpened
}

extension SessionEvent: Codable {
  private enum CodingKeys: String, CodingKey {
    case version, event, outcome, exit, reason
  }

  private enum Name: String, Codable {
    case opened, accepted, closed, rejected
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
    case .accepted:
      self = .accepted
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
    case .accepted:
      try container.encode(Name.accepted, forKey: .event)
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
