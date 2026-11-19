import Foundation
import TextBasics
import TextIO

/// Matches the patterns of ignore rules against the lines of a text, each line on its own.
///
/// A line is matched with its content as the whole range, so that `^` and `$` stand for its
/// start and end and no match reaches into another line. Matching every line on its own costs
/// more than the matching itself for most lines, so where the pattern allows it, one search of
/// the whole text first finds the lines that can match at all.
struct RuleMatcher: Sendable {
  /// The text, split into lines.
  let text: LineText

  /// The UTF-16 positions of the lines of ``text``.
  let lineIndex: LineIndex

  /// The UTF-16 code units of ``text``.
  private let utf16: [UInt16]

  /// Prepares the matching of `text`, which is valid UTF-8.
  init(text: LineText) {
    self.text = text
    lineIndex = LineIndex(utf8: text.utf8, byteLineStarts: text.lineStarts)
    utf16 = Array(String(decoding: text.utf8, as: UTF8.self).utf16)
  }

  /// The non-empty matches of `expression` in the contents of the lines, as byte ranges in
  /// text order, or `nil` if matching took longer than ``IgnoreRule/timeLimit``.
  func ranges(matching expression: NSRegularExpression) -> [Range<Int>]? {
    var deadline = Deadline(after: IgnoreRule.timeLimit)
    // A string that keeps its UTF-16 code units, which the regular expression reads without
    // copying the whole text for each line.
    let string = NSString(characters: utf16, length: utf16.count) as String
    guard let candidates = candidateLines(of: expression, in: string, before: &deadline) else {
      return nil
    }
    var ranges: [Range<Int>] = []
    var isTooSlow = false
    for line in candidates where !isTooSlow {
      let content = text.contentByteRange(ofLine: line)
      guard !content.isEmpty else { continue }
      if deadline.hasPassed() { return nil }
      let lineBytes = text.byteRange(ofLines: line..<line + 1)
      let lineUTF16 = lineIndex.utf16Range(ofLine: line)
      let contentLength = lineUTF16.count - (lineBytes.count - content.count)
      let isASCII = lineUTF16.count == lineBytes.count
      // Progress reports come during a long match too, so a pattern that backtracks without
      // end is stopped within its line.
      expression.enumerateMatches(
        in: string, options: .reportProgress,
        range: NSRange(location: lineUTF16.lowerBound, length: contentLength)
      ) { match, _, stop in
        guard !deadline.hasPassed() else {
          isTooSlow = true
          stop.pointee = true
          return
        }
        guard let match, match.range.length > 0 else { return }
        let start = match.range.location - lineUTF16.lowerBound
        let end = start + match.range.length
        let lineStart = lineBytes.lowerBound
        if isASCII {
          ranges.append((lineStart + start)..<(lineStart + end))
        } else {
          let startByte = lineIndex.byteOffset(ofUTF16Offset: start, inLine: line)
          let endByte = lineIndex.byteOffset(ofUTF16Offset: end, inLine: line)
          ranges.append((lineStart + startByte)..<(lineStart + endByte))
        }
      }
    }
    return isTooSlow ? nil : ranges
  }

  /// The lines in which `expression` may match on its own, or `nil` if the search took until
  /// `deadline`.
  ///
  /// A search of the whole text, with `^` and `$` at every line, tries each position that a
  /// search of a single line tries, and finds a match there if the line does, or one that
  /// already covers the position. So a line can only match if a match of the whole text touches
  /// it. This holds as long as the pattern cannot see past a line in another way: patterns with
  /// groups that start with `(?`, such as lookarounds and options, and with the anchors `\A`,
  /// `\z`, `\Z` and `\G` may match a line on its own but not within the text, and every line is
  /// a candidate for them.
  private func candidateLines(
    of expression: NSRegularExpression, in string: String, before deadline: inout Deadline
  ) -> IndexSet? {
    let allLines = IndexSet(integersIn: 0..<text.lineCount)
    let pattern = expression.pattern
    guard !pattern.contains("(?"), !["\\A", "\\z", "\\Z", "\\G"].contains(where: pattern.contains)
    else { return allLines }
    let wholeText: NSRegularExpression
    do {
      wholeText = try NSRegularExpression(
        pattern: pattern, options: expression.options.union(.anchorsMatchLines))
    } catch {
      return allLines
    }
    var lines = IndexSet()
    var isTooSlow = false
    wholeText.enumerateMatches(
      in: string, options: .reportProgress, range: NSRange(location: 0, length: utf16.count)
    ) { match, _, stop in
      guard !deadline.hasPassed() else {
        isTooSlow = true
        stop.pointee = true
        return
      }
      guard let range = match?.range else { return }
      let first = lineIndex.line(containingUTF16Offset: range.location)
      let last = lineIndex.line(
        containingUTF16Offset: max(range.location, range.location + range.length - 1))
      lines.insert(integersIn: first...last)
    }
    return isTooSlow ? nil : lines
  }
}

/// The moment by which matching must end, cheap enough to ask about at every step.
///
/// Matching reports progress at almost every position of the text, and reading the clock each
/// time would cost more than the matching; the clock is read at every 256th question only.
/// Within a match that backtracks without end, the reports come far apart, so it still stops
/// soon after the moment.
private struct Deadline {
  /// The moment.
  private let end: ContinuousClock.Instant

  /// How often it was asked about.
  private var questionCount = 0

  /// The moment `duration` from now.
  init(after duration: Duration) {
    end = .now + duration
  }

  /// Whether the moment has passed, as far as it is known.
  mutating func hasPassed() -> Bool {
    questionCount += 1
    return questionCount.isMultiple(of: 256) && ContinuousClock.now >= end
  }
}
