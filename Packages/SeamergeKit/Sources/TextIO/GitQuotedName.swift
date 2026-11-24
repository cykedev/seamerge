/// The names of files as Git writes them in the headers of a diff: as they are, or within quotes
/// with C-style escapes where they hold a byte that would make a header ambiguous.
package enum GitQuotedName {
  /// `prefix` and `name` as Git writes them in a header: as they are, or within quotes with
  /// escapes where they hold a quote, a backslash, a control character or a byte outside ASCII.
  ///
  /// A space alone needs no quotes; the lines `---` and `+++` end such a name with a tab.
  package static func quoted(_ name: String, prefix: String = "") -> String {
    let bytes = Array((prefix + name).utf8)
    guard bytes.contains(where: needsEscape) else { return prefix + name }
    let escaped = bytes.map { needsEscape($0) ? escape(of: $0) : String(Unicode.Scalar($0)) }
    return "\"" + escaped.joined() + "\""
  }

  /// Reads a quoted name at the start of `bytes`, which begin with a quote, and returns its bytes
  /// without quotes and escapes and how many bytes it took, closing quote included; `nil` if the
  /// quote does not close or an escape is not one Git writes.
  package static func unquoted(_ bytes: some Collection<UInt8>) -> (name: [UInt8], length: Int)? {
    var iterator = bytes.makeIterator()
    guard iterator.next() == quote else { return nil }
    var name: [UInt8] = []
    var length = 1
    while let byte = iterator.next() {
      length += 1
      switch byte {
      case quote:
        return (name, length)
      case backslash:
        guard let escaped = iterator.next() else { return nil }
        length += 1
        if let byte = unescaped[escaped] {
          name.append(byte)
        } else if let first = octalDigit(escaped) {
          guard let second = iterator.next().flatMap(octalDigit),
            let third = iterator.next().flatMap(octalDigit), first < 4
          else { return nil }
          length += 2
          name.append(first << 6 | second << 3 | third)
        } else {
          return nil
        }
      default:
        name.append(byte)
      }
    }
    return nil
  }

  private static let quote = UInt8(ascii: "\"")
  private static let backslash = UInt8(ascii: "\\")

  /// The byte that each letter of an escape stands for, and the quote and the backslash that a
  /// backslash keeps from ending or escaping.
  private static let unescaped: [UInt8: UInt8] = [
    UInt8(ascii: "a"): 0x07, UInt8(ascii: "b"): 0x08, UInt8(ascii: "t"): 0x09,
    UInt8(ascii: "n"): 0x0A, UInt8(ascii: "v"): 0x0B, UInt8(ascii: "f"): 0x0C,
    UInt8(ascii: "r"): 0x0D, quote: quote, backslash: backslash,
  ]

  /// The value of `byte` as an octal digit, or `nil` if it is none.
  private static func octalDigit(_ byte: UInt8) -> UInt8? {
    (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(byte) ? byte - UInt8(ascii: "0") : nil
  }

  /// The escape Git writes for `byte`: a letter for the usual control characters, a backslash
  /// before a quote or a backslash, three octal digits for any other byte.
  private static func escape(of byte: UInt8) -> String {
    if let letter = unescaped.first(where: { $0.value == byte && $0.key != byte })?.key {
      return "\\" + String(Unicode.Scalar(letter))
    }
    if byte == quote || byte == backslash {
      return "\\" + String(Unicode.Scalar(byte))
    }
    let digits = String(byte, radix: 8)
    return "\\" + String(repeating: "0", count: 3 - digits.count) + digits
  }

  /// Whether Git writes `byte` of a name as an escape.
  private static func needsEscape(_ byte: UInt8) -> Bool {
    byte < 0x20 || byte >= 0x7F || byte == quote || byte == backslash
  }
}
