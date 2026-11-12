/// The UTF-8 bytes of one line, without its line break.
///
/// Positions are byte offsets from the start of the line. Reading past the end yields `nil`
/// rather than trapping, so the lexers can look ahead without checking the length first.
///
/// Every read of a byte goes through `read(_:)`, which can count the reads: their number is
/// the work of lexing, and shows that it grows in proportion to the length of the input.
struct LineBytes {
  private let bytes: UnsafeBufferPointer<UInt8>
  private let readCount: UnsafeMutablePointer<Int>?

  /// The number of bytes before the line break.
  let count: Int

  /// The line in `bytes`, which may end in a line feed, a carriage return or both.
  ///
  /// - Parameter readCount: A count to which every byte read from the line is added.
  init(_ bytes: UnsafeBufferPointer<UInt8>, readCount: UnsafeMutablePointer<Int>? = nil) {
    var count = bytes.count
    while count > 0, bytes[count - 1] == .lineFeed || bytes[count - 1] == .carriageReturn {
      count -= 1
    }
    self.bytes = bytes
    self.readCount = readCount
    self.count = count
  }

  private func read(_ position: Int) -> UInt8 {
    readCount?.pointee += 1
    return bytes[position]
  }

  /// The byte at a position before the end.
  subscript(position: Int) -> UInt8 {
    precondition(position < count, "Position \(position) is past the end of the line")
    return read(position)
  }

  /// The byte at a position, or `nil` at or past the end.
  func byte(at position: Int) -> UInt8? {
    position < count ? read(position) : nil
  }

  /// The bytes in a range of the line.
  func bytes(in range: Range<Int>) -> [UInt8] {
    range.map(read)
  }

  /// Whether the bytes at a position are those of `pattern`.
  func hasPrefix(_ pattern: [UInt8], at position: Int) -> Bool {
    guard position + pattern.count <= count else { return false }
    for (offset, byte) in pattern.enumerated() where read(position + offset) != byte {
      return false
    }
    return true
  }

  /// Whether the bytes at a position are those of `pattern`, ignoring the case of ASCII
  /// letters.
  ///
  /// - Precondition: `pattern` is in lowercase.
  func hasPrefix(lowercased pattern: [UInt8], at position: Int) -> Bool {
    guard position + pattern.count <= count else { return false }
    for (offset, byte) in pattern.enumerated()
    where read(position + offset).lowercasedASCII != byte {
      return false
    }
    return true
  }

  /// The position after the spaces and tabs that start at `position`.
  func skippingSpaces(from position: Int) -> Int {
    var position = position
    while position < count, read(position).isSpaceOrTab { position += 1 }
    return position
  }

  /// The position of the first byte of a kind at or after `position`, or `nil` if there is
  /// none.
  func firstPosition(of byte: UInt8, from position: Int) -> Int? {
    var position = position
    while position < count {
      if read(position) == byte { return position }
      position += 1
    }
    return nil
  }
}

extension UInt8 {
  static let lineFeed = UInt8(ascii: "\n")
  static let carriageReturn = UInt8(ascii: "\r")
  static let underscore = UInt8(ascii: "_")

  var isASCIIDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }

  var isASCIILetter: Bool {
    let lowercased = self | 0x20
    return lowercased >= UInt8(ascii: "a") && lowercased <= UInt8(ascii: "z")
  }

  var isSpaceOrTab: Bool { self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") }

  var lowercasedASCII: UInt8 { isASCIILetter ? self | 0x20 : self }
}
