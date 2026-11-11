/// A sequence of control characters that ends a line.
public enum LineEnding: Sendable, Hashable, CaseIterable {
  /// A line feed, as on macOS, Linux and other Unix systems.
  case lf

  /// A carriage return followed by a line feed, as on Windows.
  case crlf

  /// A carriage return alone, as on classic Mac OS.
  case cr

  /// The UTF-8 bytes of the line ending.
  var utf8: [UInt8] {
    switch self {
    case .lf: [ASCII.lineFeed]
    case .crlf: [ASCII.carriageReturn, ASCII.lineFeed]
    case .cr: [ASCII.carriageReturn]
    }
  }
}

/// How often each kind of line ending occurs in a text.
public struct LineEndingCounts: Sendable, Hashable {
  /// The number of line feeds that do not follow a carriage return.
  public var lf: Int

  /// The number of carriage returns followed by a line feed.
  public var crlf: Int

  /// The number of carriage returns that no line feed follows.
  public var cr: Int

  /// Creates counts with the given number of each line ending.
  public init(lf: Int = 0, crlf: Int = 0, cr: Int = 0) {
    self.lf = lf
    self.crlf = crlf
    self.cr = cr
  }

  /// The number of line endings of any kind.
  public var total: Int { lf + crlf + cr }

  /// The number of occurrences of `lineEnding`.
  public subscript(lineEnding: LineEnding) -> Int {
    switch lineEnding {
    case .lf: lf
    case .crlf: crlf
    case .cr: cr
    }
  }

  /// The line ending that occurs most often, or `nil` if there is none.
  ///
  /// A tie goes to the line ending that comes first in ``LineEnding/allCases``.
  public var majority: LineEnding? {
    guard total > 0 else { return nil }
    return LineEnding.allCases.reduce(LineEnding.lf) { self[$1] > self[$0] ? $1 : $0 }
  }

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

/// The line endings of a text that has at least one line break.
public enum LineEndingStyle: Sendable, Hashable {
  /// Every line break is the same line ending.
  case uniform(LineEnding)

  /// The text mixes line endings, with the count of each.
  case mixed(LineEndingCounts)

  /// Creates the style that `counts` describe, or `nil` if the text has no line break.
  init?(_ counts: LineEndingCounts) {
    let used = LineEnding.allCases.filter { counts[$0] > 0 }
    switch used.count {
    case 0: return nil
    case 1: self = .uniform(used[0])
    default: self = .mixed(counts)
    }
  }

  /// The line ending a text in this style is written with by default: its only one, or the most
  /// frequent one of a mixed text.
  public var predominantLineEnding: LineEnding {
    switch self {
    case .uniform(let lineEnding):
      lineEnding
    case .mixed(let counts):
      // A mixed style has at least two kinds of line ending, so there is a majority.
      counts.majority ?? .lf
    }
  }
}

/// The ASCII bytes that line endings consist of.
enum ASCII {
  static let lineFeed: UInt8 = 0x0A
  static let carriageReturn: UInt8 = 0x0D
}
