/// A sequence of control characters that ends a line.
public enum LineEnding: Sendable, Hashable, CaseIterable {
  /// A line feed, as on macOS, Linux and other Unix systems.
  case lf

  /// A carriage return followed by a line feed, as on Windows.
  case crlf

  /// A carriage return alone, as on classic Mac OS.
  case cr
}

/// How often each kind of line ending occurs in a text.
public struct LineEndingCounts: Sendable, Hashable {
  /// The number of line feeds that do not follow a carriage return.
  package var lf: Int

  /// The number of carriage returns followed by a line feed.
  package var crlf: Int

  /// The number of carriage returns that no line feed follows.
  package var cr: Int

  /// Creates counts with the given number of each line ending.
  package init(lf: Int = 0, crlf: Int = 0, cr: Int = 0) {
    self.lf = lf
    self.crlf = crlf
    self.cr = cr
  }

  /// The number of line endings of any kind.
  package var total: Int { lf + crlf + cr }

  /// The number of occurrences of `lineEnding`.
  package subscript(lineEnding: LineEnding) -> Int {
    switch lineEnding {
    case .lf: lf
    case .crlf: crlf
    case .cr: cr
    }
  }

  /// The line ending that occurs most often, or `nil` if there is none.
  ///
  /// A tie goes to the line ending that comes first in ``LineEnding/allCases``.
  package var majority: LineEnding? {
    guard total > 0 else { return nil }
    return LineEnding.allCases.reduce(LineEnding.lf) { self[$1] > self[$0] ? $1 : $0 }
  }
}

/// The line endings of a text that has at least one line break.
public enum LineEndingStyle: Sendable, Hashable {
  /// Every line break is the same line ending.
  case uniform(LineEnding)

  /// The text mixes line endings, with the count of each.
  case mixed(LineEndingCounts)

  /// Creates the style that `counts` describe, or `nil` if the text has no line break.
  package init?(_ counts: LineEndingCounts) {
    let used = LineEnding.allCases.filter { counts[$0] > 0 }
    switch used.count {
    case 0: return nil
    case 1: self = .uniform(used[0])
    default: self = .mixed(counts)
    }
  }

  /// The line ending a text in this style is written with by default: its only one, or the most
  /// frequent one of a mixed text.
  package var predominantLineEnding: LineEnding {
    switch self {
    case .uniform(let lineEnding):
      lineEnding
    case .mixed(let counts):
      // A mixed style has at least two kinds of line ending, so there is a majority.
      counts.majority ?? .lf
    }
  }
}
