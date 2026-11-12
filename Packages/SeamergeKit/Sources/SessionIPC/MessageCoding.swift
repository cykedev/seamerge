import Foundation

/// Turns messages into lines of JSON and back.
///
/// Every message is one line: JSON never contains a raw line feed, so the line feed after it ends
/// the message. Every message carries the version of the protocol, and only the same version is
/// understood.
enum MessageCoding {
  /// The version of the protocol this module speaks.
  static let version = 2

  /// The line feed that ends every message.
  static let lineFeed = UInt8(ascii: "\n")

  /// Encodes a message as one line, including the line feed that ends it.
  static func line(for message: some Encodable) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      var line = try encoder.encode(message)
      line.append(lineFeed)
      return line
    } catch {
      preconditionFailure("A session message failed to encode: \(error)")
    }
  }

  /// Decodes a message from a line without its line feed.
  ///
  /// - Throws: ``SessionError/unsupportedVersion(_:)`` if the line is a message of another version,
  ///   ``SessionError/malformedMessage(_:)`` if it is not a message of the expected type.
  static func decode<Message: Decodable>(
    _ type: Message.Type, from line: Data
  ) throws(SessionError) -> Message {
    do {
      return try JSONDecoder().decode(type, from: line)
    } catch let error as SessionError {
      throw error
    } catch {
      throw .malformedMessage(String(describing: error))
    }
  }

  /// Reads the version of a message and throws if it is not the version of this module.
  static func checkVersion<Key>(
    in container: KeyedDecodingContainer<Key>, forKey key: Key
  ) throws {
    let found = try container.decode(Int.self, forKey: key)
    guard found == version else { throw SessionError.unsupportedVersion(found) }
  }
}

extension KeyedEncodingContainer {
  /// Encodes a file URL as its path.
  mutating func encodeFileURL(_ url: URL, forKey key: Key) throws {
    try encode(url.path(percentEncoded: false), forKey: key)
  }

  /// Encodes a file URL as its path if it is not `nil`.
  mutating func encodeFileURLIfPresent(_ url: URL?, forKey key: Key) throws {
    guard let url else { return }
    try encodeFileURL(url, forKey: key)
  }
}

extension KeyedDecodingContainer {
  /// Decodes a file URL from an absolute path.
  func decodeFileURL(forKey key: Key) throws -> URL {
    let path = try decode(String.self, forKey: key)
    guard path.hasPrefix("/") else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "\(path) is not an absolute path.")
    }
    return URL(filePath: path)
  }

  /// Decodes a file URL from an absolute path, or `nil` if there is none.
  func decodeFileURLIfPresent(forKey key: Key) throws -> URL? {
    try contains(key) ? decodeFileURL(forKey: key) : nil
  }
}
