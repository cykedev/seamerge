import TextBasics

extension LineEnding {
  /// The UTF-8 bytes of the line ending.
  var utf8: [UInt8] {
    switch self {
    case .lf: [ASCII.lineFeed]
    case .crlf: [ASCII.carriageReturn, ASCII.lineFeed]
    case .cr: [ASCII.carriageReturn]
    }
  }
}

extension LineEndingCounts {
  /// Counts the line endings in UTF-8 encoded text.
  init(utf8 bytes: UnsafeRawBufferPointer) {
    self.init()
    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case ASCII.lineFeed:
        lf += 1
      case ASCII.carriageReturn:
        if index + 1 < bytes.count, bytes[index + 1] == ASCII.lineFeed {
          crlf += 1
          index += 1
        } else {
          cr += 1
        }
      default:
        break
      }
      index += 1
    }
  }
}

/// The ASCII bytes that line endings consist of.
enum ASCII {
  static let lineFeed: UInt8 = 0x0A
  static let carriageReturn: UInt8 = 0x0D
}
