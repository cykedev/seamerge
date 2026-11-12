import Foundation

/// Decides which changed runs of a token comparison the comparison mode ignores.
///
/// Only whitespace and line endings are ever ignored, and only as far as the mode ignores them
/// between lines:
/// - ``ComparisonMode/ignoreLineEndings``: one line ending replaced by another.
/// - ``ComparisonMode/ignoreWhitespaceAmount``: whitespace replaced by other whitespace, and
///   spaces or tabs added or removed at the end of a line.
/// - ``ComparisonMode/ignoreAllWhitespace``: whitespace replaced by other whitespace, and spaces
///   or tabs added or removed anywhere.
///
/// A run that adds or removes a line break is never ignored, even when both sides are only
/// whitespace, because it joins or splits lines: a space replaced by a line ending is a change.
struct ChangeFilter {
  /// The comparison mode.
  let mode: ComparisonMode

  /// The text the runs' first ranges refer to, starting at index 0.
  let first: Data

  /// The text the runs' second ranges refer to, starting at index 0.
  let second: Data

  /// Whether the mode ignores the change of `run`.
  func ignores(_ run: EngineAdapter.TokenComparison.Run) -> Bool {
    let firstRun = first[run.first]
    let secondRun = second[run.second]
    switch mode {
    case .exact:
      return false
    case .ignoreLineEndings:
      return !firstRun.isEmpty && !secondRun.isEmpty
        && firstRun.allSatisfy(Self.isLineEnding) && secondRun.allSatisfy(Self.isLineEnding)
        && Self.lineBreakCount(firstRun) == Self.lineBreakCount(secondRun)
    case .ignoreWhitespaceAmount, .ignoreAllWhitespace:
      guard firstRun.allSatisfy(Self.isWhitespace), secondRun.allSatisfy(Self.isWhitespace)
      else { return false }
      if !firstRun.isEmpty && !secondRun.isEmpty {
        return Self.lineBreakCount(firstRun) == Self.lineBreakCount(secondRun)
      }
      let (text, range) = firstRun.isEmpty ? (second, run.second) : (first, run.first)
      guard text[range].allSatisfy(Self.isBlank) else { return false }
      return mode == .ignoreAllWhitespace || range.upperBound == text.count
        || Self.isLineEnding(text[range.upperBound])
    }
  }

  /// The number of line breaks in `text`, counting CRLF as one.
  ///
  /// A run never ends between the CR and the LF of a CRLF, because the comparison keeps them in
  /// one token.
  private static func lineBreakCount(_ text: Data) -> Int {
    var count = 0
    var previous: UInt8 = 0
    for byte in text {
      if byte == UInt8(ascii: "\r")
        || (byte == UInt8(ascii: "\n") && previous != UInt8(ascii: "\r"))
      {
        count += 1
      }
      previous = byte
    }
    return count
  }

  private static func isBlank(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
  }

  private static func isLineEnding(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    isBlank(byte) || isLineEnding(byte)
  }
}
