import Foundation
import TextBasics

/// The work is coded with names of its own for every case, so that renaming a case in the code
/// never changes the format, and decoding checks everything that restoring relies on.
extension MergeWork: Codable {
  private enum CodingKeys: String, CodingKey {
    case formatVersion
    case key
    case savedAt
    case mode
    case encoding
    case byteOrderMark
    case lineEnding
    case blocks
    case currentBlock
    case text
    case segments
  }

  private enum SegmentKeys: String, CodingKey {
    case length
    case state
    case sources
    case bytes
  }

  private enum PlaceKeys: String, CodingKey {
    case index
    case bytes
  }

  /// Encodes the work together with ``formatVersion``.
  ///
  /// The time is written as seconds since the reference date of `Date`, which decodes to the same
  /// time exactly.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.formatVersion, forKey: .formatVersion)
    try container.encode(key.rawValue, forKey: .key)
    try container.encode(savedAt.timeIntervalSinceReferenceDate, forKey: .savedAt)
    try container.encode(mode.codingName, forKey: .mode)
    try container.encode(format.encoding.codingName, forKey: .encoding)
    try container.encode(format.writesByteOrderMark, forKey: .byteOrderMark)
    try container.encode(format.lineEnding.codingName, forKey: .lineEnding)
    try container.encode(blockFingerprint, forKey: .blocks)
    if let currentBlock {
      var place = container.nestedContainer(keyedBy: PlaceKeys.self, forKey: .currentBlock)
      try place.encode(currentBlock.index, forKey: .index)
      try place.encode(currentBlock.byteRanges.map(\.bounds), forKey: .bytes)
    }
    try container.encode(text, forKey: .text)
    var segments = container.nestedUnkeyedContainer(forKey: .segments)
    for segment in self.segments {
      var saved = segments.nestedContainer(keyedBy: SegmentKeys.self)
      try saved.encodeIfPresent(segment.length, forKey: .length)
      if let decision = segment.decision {
        try saved.encode(decision.state.codingName, forKey: .state)
        try saved.encode(decision.sources.map(\.codingName), forKey: .sources)
        try saved.encode(decision.byteRanges.map(\.bounds), forKey: .bytes)
      }
    }
  }

  /// Decodes work of the current ``formatVersion``.
  ///
  /// - Throws: `DecodingError` if the data is no work of this format version, or if a value is
  ///   out of place: an unknown name, a negative length or offset, segments whose lengths do not
  ///   add up to the text, or a decision that only a conflict as loaded can have.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .formatVersion)
    guard version == Self.formatVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .formatVersion, in: container,
        debugDescription: "Format version \(version) is not \(Self.formatVersion)")
    }
    let rawKey = try container.decode(String.self, forKey: .key)
    guard let key = MergeKey(rawValue: rawKey) else {
      throw DecodingError.dataCorruptedError(
        forKey: .key, in: container, debugDescription: "\(rawKey) is no key")
    }
    let savedAt = try container.decode(Double.self, forKey: .savedAt)
    let encoding = try container.decodeName(FileEncoding.self, forKey: .encoding)
    let writesByteOrderMark = try container.decode(Bool.self, forKey: .byteOrderMark)
    guard !writesByteOrderMark || encoding.supportsByteOrderMark else {
      throw DecodingError.dataCorruptedError(
        forKey: .byteOrderMark, in: container, debugDescription: "\(encoding) has no mark")
    }
    let fingerprint = try container.decode(String.self, forKey: .blocks)
    guard MergeKey(rawValue: fingerprint) != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .blocks, in: container, debugDescription: "\(fingerprint) is no fingerprint")
    }
    var currentBlock: BlockPlace?
    if container.contains(.currentBlock) {
      let place = try container.nestedContainer(keyedBy: PlaceKeys.self, forKey: .currentBlock)
      currentBlock = BlockPlace(
        index: try place.decodeCount(forKey: .index),
        byteRanges: try place.decodeByteRanges(forKey: .bytes))
    }
    let text = try container.decode(String.self, forKey: .text)
    var segmentsContainer = try container.nestedUnkeyedContainer(forKey: .segments)
    var segments: [SavedSegment] = []
    var keptLength = 0
    while !segmentsContainer.isAtEnd {
      let segment = try Self.decodeSegment(
        from: segmentsContainer.nestedContainer(keyedBy: SegmentKeys.self))
      keptLength += segment.length ?? 0
      segments.append(segment)
    }
    guard keptLength == text.utf16.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .segments, in: container,
        debugDescription: "The segments hold \(keptLength) of \(text.utf16.count) code units")
    }
    self.init(
      key: key, savedAt: Date(timeIntervalSinceReferenceDate: savedAt),
      mode: try container.decodeName(ComparisonMode.self, forKey: .mode),
      format: ResultFormat(
        encoding: encoding, writesByteOrderMark: writesByteOrderMark,
        lineEnding: try container.decodeName(LineEnding.self, forKey: .lineEnding)),
      text: text, blockFingerprint: fingerprint, segments: segments, currentBlock: currentBlock)
  }

  /// The segment that `container` holds: a length, unless it is an open conflict, and a
  /// decision, unless it is as loaded.
  private static func decodeSegment(
    from container: KeyedDecodingContainer<SegmentKeys>
  ) throws -> SavedSegment {
    var segment = SavedSegment(
      length: container.contains(.length) ? try container.decodeCount(forKey: .length) : nil)
    guard container.contains(.state) else { return segment }
    let state = try container.decodeName(Segment.State.self, forKey: .state)
    guard state != .open, segment.length != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .state, in: container,
        debugDescription: "Only a conflict as loaded is open, and it has no length")
    }
    let sources = try container.decode([String].self, forKey: .sources).map { name in
      guard let role = Role(codingName: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: .sources, in: container, debugDescription: "\(name) is no input")
      }
      return role
    }
    segment.decision = Decision(
      state: state, sources: sources, byteRanges: try container.decodeByteRanges(forKey: .bytes))
    return segment
  }
}

extension KeyedDecodingContainer {
  /// The value of a type that the work codes by name.
  fileprivate func decodeName<Value: NamedInWork>(
    _ type: Value.Type, forKey key: Key
  ) throws -> Value {
    let name = try decode(String.self, forKey: key)
    guard let value = Value(codingName: name) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "\(name) is no \(Value.self)")
    }
    return value
  }

  /// A number that is not negative, such as a length or a position.
  fileprivate func decodeCount(forKey key: Key) throws -> Int {
    let count = try decode(Int.self, forKey: key)
    guard count >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "\(count) is negative")
    }
    return count
  }

  /// The ranges of bytes in base, A and B, each as its two bounds.
  fileprivate func decodeByteRanges(forKey key: Key) throws -> [Range<Int>] {
    let bounds = try decode([[Int]].self, forKey: key)
    guard bounds.count == Role.allCases.count,
      bounds.allSatisfy({ $0.count == 2 && 0 <= $0[0] && $0[0] <= $0[1] })
    else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "\(bounds) are no ranges of base, A and B")
    }
    return bounds.map { $0[0]..<$0[1] }
  }
}

extension Range<Int> {
  /// The lower and the upper bound, as the work codes a range.
  fileprivate var bounds: [Int] { [lowerBound, upperBound] }
}

/// A type whose values the work codes by a name of its own.
private protocol NamedInWork {
  /// Every value of the type.
  static var namedValues: [Self] { get }

  /// The name of the value in the work.
  var codingName: String { get }
}

extension NamedInWork {
  /// The value named `codingName`, or `nil` if there is none.
  init?(codingName: String) {
    guard let value = Self.namedValues.first(where: { $0.codingName == codingName }) else {
      return nil
    }
    self = value
  }
}

extension NamedInWork where Self: CaseIterable {
  static var namedValues: [Self] { Array(allCases) }
}

extension ComparisonMode: NamedInWork {
  fileprivate var codingName: String {
    switch self {
    case .exact: "exact"
    case .ignoreLineEndings: "ignoreLineEndings"
    case .ignoreWhitespaceAmount: "ignoreWhitespaceAmount"
    case .ignoreAllWhitespace: "ignoreAllWhitespace"
    }
  }
}

extension FileEncoding: NamedInWork {
  fileprivate var codingName: String {
    switch self {
    case .utf8: "utf8"
    case .utf16LittleEndian: "utf16LittleEndian"
    case .utf16BigEndian: "utf16BigEndian"
    case .utf32LittleEndian: "utf32LittleEndian"
    case .utf32BigEndian: "utf32BigEndian"
    case .windows1252: "windows1252"
    case .isoLatin1: "isoLatin1"
    case .macRoman: "macRoman"
    }
  }
}

extension LineEnding: NamedInWork {
  fileprivate var codingName: String {
    switch self {
    case .lf: "lf"
    case .crlf: "crlf"
    case .cr: "cr"
    }
  }
}

extension Role: NamedInWork {
  fileprivate var codingName: String {
    switch self {
    case .base: "base"
    case .a: "a"
    case .b: "b"
    }
  }
}

extension Segment.State: NamedInWork {
  fileprivate static let namedValues: [Self] = [.untouched, .auto, .chosen, .edited, .open]

  fileprivate var codingName: String {
    switch self {
    case .untouched: "untouched"
    case .auto: "auto"
    case .chosen: "chosen"
    case .edited: "edited"
    case .open: "open"
    }
  }
}
