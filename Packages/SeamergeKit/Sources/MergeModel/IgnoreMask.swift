import Foundation
import TextBasics
import TextIO

/// A file as a comparison with ignore rules sees it: without the text that the rules match,
/// line for line.
///
/// Every line of the mask belongs to the line of the file with the same index, and each keeps
/// its line ending. A line whose text the rules match entirely becomes a single
/// ``placeholder``, so that it is never equal to a blank line, which counts as a change of its
/// own, and so that nothing new stands between a CR and the LF of the next line. A line that the
/// comparison mode already counts as blank is never matched. The mask only goes to the engine;
/// the file is shown, copied and saved as it is.
struct IgnoreMask: Sendable {
  /// The byte that stands for a line the rules match entirely; it never occurs in UTF-8.
  static let placeholder: UInt8 = 0xFF

  /// The text of the file, split as the comparison mode splits it.
  let text: LineText

  /// The UTF-16 positions of the lines of ``text``.
  let lineIndex: LineIndex

  /// The text without the matched text, with as many lines as ``text``.
  let masked: LineText

  /// The text that the rules match.
  let matches: RuleMatches

  /// Masks the matched `ranges` of `text`.
  ///
  /// - Parameters:
  ///   - ranges: Ranges within the contents of lines, sorted by their start; overlapping and
  ///     touching ranges are joined.
  ///   - mode: The comparison mode, which decides whether whitespace left over in a line counts.
  init(text: LineText, lineIndex: LineIndex, ranges: [Range<Int>], mode: ComparisonMode) {
    var joined: [Range<Int>] = []
    for range in ranges {
      if let last = joined.last, range.lowerBound <= last.upperBound {
        joined[joined.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        joined.append(range)
      }
    }
    var masked: [UInt8] = []
    masked.reserveCapacity(text.utf8.count)
    var maskedStarts = [0]
    maskedStarts.reserveCapacity(text.lineCount + 1)
    var kept: [Range<Int>] = []
    kept.reserveCapacity(joined.count)
    var entireLines = IndexSet()
    var next = 0
    text.utf8.withUnsafeBytes { bytes in
      for line in 0..<text.lineCount {
        let content = text.contentByteRange(ofLine: line)
        let start = masked.count
        var position = content.lowerBound
        var isMatched = false
        // A line that the mode already counts as blank stays a blank line, whatever matches it.
        let isBlank = Self.countsAsEmpty(bytes[content], in: mode)
        while next < joined.count, joined[next].lowerBound < content.upperBound {
          if !isBlank {
            masked.append(contentsOf: bytes[position..<joined[next].lowerBound])
            position = joined[next].upperBound
            isMatched = true
            kept.append(joined[next])
          }
          next += 1
        }
        masked.append(contentsOf: bytes[position..<content.upperBound])
        if isMatched, Self.countsAsEmpty(masked[start...], in: mode) {
          masked.removeSubrange(start...)
          masked.append(Self.placeholder)
          entireLines.insert(line)
        }
        masked.append(contentsOf: bytes[content.upperBound..<text.lineStarts[line + 1]])
        maskedStarts.append(masked.count)
      }
    }
    self.text = text
    self.lineIndex = lineIndex
    self.masked = LineText(utf8: Data(masked), lineStarts: LineStarts(maskedStarts))
    matches = RuleMatches(ranges: kept, entireLines: entireLines)
  }

  /// Whether the text of a line, or what the rules leave of it, counts as nothing in `mode`:
  /// nothing at all, or in the modes that ignore the amount of whitespace, only spaces and tabs.
  private static func countsAsEmpty(
    _ remainder: some Collection<UInt8>, in mode: ComparisonMode
  ) -> Bool {
    switch mode {
    case .exact, .ignoreLineEndings:
      remainder.isEmpty
    case .ignoreWhitespaceAmount, .ignoreAllWhitespace:
      remainder.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
    }
  }
}

extension IgnoreMask {
  /// The masks of `texts` and the rules that took longer than ``IgnoreRule/timeLimit`` for one
  /// of them.
  ///
  /// Each rule is matched against each text in a task of its own. A rule that exceeds the limit
  /// for one text masks none, since masking only one side would make differences of its own.
  ///
  /// - Parameters:
  ///   - texts: The compared text of each input, valid UTF-8.
  ///   - rules: Rules whose patterns are valid, each with its compiled pattern.
  static func masks(
    of texts: Session.Inputs<Data>, rules: [(rule: IgnoreRule, expression: NSRegularExpression)],
    mode: ComparisonMode
  ) async -> (masks: Session.Inputs<IgnoreMask>, slowRules: Set<IgnoreRule>) {
    let files = texts.mapValues { RuleMatcher(text: LineText(splitting: $0, in: mode)) }
    let found = await matches(of: rules, in: Array(files))
    let masks = files.mapValuesWithRoles { role, file in
      IgnoreMask(file, ranges: found.ranges[role] ?? [], mode: mode)
    }
    return (masks, found.slowRules)
  }

  /// The mask of `text`, valid UTF-8, and the rules of `rules` that took longer than
  /// ``IgnoreRule/timeLimit`` for it, which mask nothing.
  static func mask(
    of text: Data, rules: [(rule: IgnoreRule, expression: NSRegularExpression)],
    mode: ComparisonMode
  ) async -> (mask: IgnoreMask, slowRules: Set<IgnoreRule>) {
    let file = RuleMatcher(text: LineText(splitting: text, in: mode))
    let found = await matches(of: rules, in: [(.a, file)])
    return (IgnoreMask(file, ranges: found.ranges[.a] ?? [], mode: mode), found.slowRules)
  }

  /// The mask of the text of `file` that hides `ranges`, in any order.
  private init(_ file: RuleMatcher, ranges: [Range<Int>], mode: ComparisonMode) {
    self.init(
      text: file.text, lineIndex: file.lineIndex,
      ranges: ranges.sorted { $0.lowerBound < $1.lowerBound }, mode: mode)
  }

  /// The ranges that `rules` match in each of `files`, without those of the rules that took
  /// longer than ``IgnoreRule/timeLimit`` for one of them, which are listed apart.
  private static func matches(
    of rules: [(rule: IgnoreRule, expression: NSRegularExpression)],
    in files: [(role: Role, value: RuleMatcher)]
  ) async -> (ranges: [Role: [Range<Int>]], slowRules: Set<IgnoreRule>) {
    let matches = await withTaskGroup(
      of: (role: Role, rule: Int, ranges: [Range<Int>]?).self
    ) { group in
      for (role, file) in files {
        for (index, rule) in rules.enumerated() {
          group.addTask { (role, index, file.ranges(matching: rule.expression)) }
        }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    let slowIndices = Set(matches.filter { $0.ranges == nil }.map(\.rule))
    var rangesByRole: [Role: [Range<Int>]] = [:]
    for match in matches where !slowIndices.contains(match.rule) {
      rangesByRole[match.role, default: []].append(contentsOf: match.ranges ?? [])
    }
    return (rangesByRole, Set(slowIndices.map { rules[$0].rule }))
  }
}
