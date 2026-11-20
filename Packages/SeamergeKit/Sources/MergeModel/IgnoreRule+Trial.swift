import Foundation

extension IgnoreRule {
  /// What a rule does to a sample text.
  public enum Trial: Sendable, Hashable {
    /// The rule takes effect and leaves out these characters, as UTF-16 offsets from the start
    /// of the text, in text order; neither overlaps nor touches the next.
    case matches([Range<Int>])

    /// The rule takes no effect, for this reason.
    case problem(Problem)
  }

  /// Tries the rule on `text` as a comparison in `mode` applies it to the lines of a file, so
  /// that the matches are exactly the text that such a comparison leaves out.
  ///
  /// The rule counts as enabled. A line that `mode` counts as blank keeps its text, as in a
  /// comparison. The matching runs off the calling actor and ends after
  /// ``IgnoreRule/timeLimit``, which is then the problem.
  @concurrent
  public func trial(on text: String, mode: ComparisonMode) async -> Trial {
    let expression: NSRegularExpression
    switch validated() {
    case .valid(let valid): expression = valid
    case .invalid(let problem): return .problem(problem)
    }
    // A comparison sees the text of a file whose lines all end in CR with LFs in exact mode;
    // either way every offset stays the same. A text with a NUL byte counts as binary, and a
    // comparison would not take it.
    guard let compared = SourceFile(bytes: Data(text.utf8), label: "").comparedText(in: mode)
    else { return .matches([]) }
    let masking = await IgnoreMask.mask(of: compared, rules: [(self, expression)], mode: mode)
    guard masking.slowRules.isEmpty else { return .problem(.exceedsTimeLimit) }
    return .matches(Self.utf16Ranges(of: masking.mask.matches.ranges, in: text))
  }

  /// The UTF-16 offsets in `text` of `byteRanges`, sorted UTF-8 offsets that each start and end
  /// on a character boundary.
  private static func utf16Ranges(of byteRanges: [Range<Int>], in text: String) -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    ranges.reserveCapacity(byteRanges.count)
    var byte = 0
    var utf16 = 0
    var index = text.utf8.startIndex
    // Both views advance together through the text once, since the ranges come in text order.
    func advance(toByte target: Int) -> Int {
      let next = text.utf8.index(index, offsetBy: target - byte)
      utf16 += text.utf16.distance(from: index, to: next)
      index = next
      byte = target
      return utf16
    }
    for range in byteRanges {
      let start = advance(toByte: range.lowerBound)
      let end = advance(toByte: range.upperBound)
      ranges.append(start..<end)
    }
    return ranges
  }
}
