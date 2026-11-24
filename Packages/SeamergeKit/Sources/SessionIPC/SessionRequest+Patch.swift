public import Foundation

extension SessionRequest {
  /// A unified diff to show in a window that nothing can change: its text, which the tool read
  /// from a file or from standard input, rather than a path to it.
  ///
  /// The message carries the bytes of the patch as they were read, in Base64, since a patch may
  /// hold lines of files in other encodings than UTF-8.
  public struct Patch: Sendable, Hashable {
    /// The largest patch a request carries, in bytes.
    public static let maximumByteCount = 128 << 20

    /// The bytes of the patch.
    public var text: Data

    /// The name of the file the patch was read from, without its folders, or `nil` for a patch
    /// read from standard input.
    public var fileName: String?

    /// Whether the tool waits until the window closes, rather than ending once it shows.
    public var waitsForWindow: Bool

    /// Creates the description of a patch.
    public init(text: Data, fileName: String? = nil, waitsForWindow: Bool = false) {
      self.text = text
      self.fileName = fileName
      self.waitsForWindow = waitsForWindow
    }
  }
}

extension SessionRequest.Patch: Codable {
  private enum CodingKeys: String, CodingKey {
    case text, fileName, wait
  }

  /// Decodes a patch; one larger than ``maximumByteCount`` cannot be decoded.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(Data.self, forKey: .text)
    guard text.count <= Self.maximumByteCount else {
      throw DecodingError.dataCorruptedError(
        forKey: .text, in: container, debugDescription: "The patch is larger than a request holds.")
    }
    fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
    waitsForWindow = try container.decodeIfPresent(Bool.self, forKey: .wait) ?? false
  }

  /// Encodes the patch; `wait` only where the tool waits.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(text, forKey: .text)
    try container.encodeIfPresent(fileName, forKey: .fileName)
    if waitsForWindow {
      try container.encode(true, forKey: .wait)
    }
  }
}
