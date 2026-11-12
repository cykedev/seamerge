/// A set of bytes with constant-time membership, for classifying characters while lexing.
struct ByteSet: Sendable, Hashable {
  private var low: UInt128 = 0
  private var high: UInt128 = 0

  /// The empty set.
  init() {}

  /// The UTF-8 bytes of the characters.
  init(_ characters: some Sequence<Character>) {
    for character in characters {
      for byte in character.utf8 { insert(byte) }
    }
  }

  /// The bytes in a range.
  init(_ bytes: ClosedRange<UInt8>) {
    for byte in bytes { insert(byte) }
  }

  /// ASCII letters, digits and the underscore.
  static let asciiWordCharacters = ByteSet(UInt8(ascii: "a")...UInt8(ascii: "z"))
    .union(ByteSet(UInt8(ascii: "A")...UInt8(ascii: "Z")))
    .union(ByteSet(UInt8(ascii: "0")...UInt8(ascii: "9")))
    .union(ByteSet(["_"]))

  /// Every byte that is not ASCII, which is part of a word so that `café` stays one word.
  static let nonASCII = ByteSet(0x80...0xFF)

  mutating func insert(_ byte: UInt8) {
    if byte < 128 { low |= 1 << byte } else { high |= 1 << (byte - 128) }
  }

  func contains(_ byte: UInt8) -> Bool {
    if byte < 128 { low >> byte & 1 == 1 } else { high >> (byte - 128) & 1 == 1 }
  }

  func subtracting(_ other: ByteSet) -> ByteSet {
    var difference = self
    difference.low &= ~other.low
    difference.high &= ~other.high
    return difference
  }

  func union(_ other: ByteSet) -> ByteSet {
    var union = self
    union.low |= other.low
    union.high |= other.high
    return union
  }
}
