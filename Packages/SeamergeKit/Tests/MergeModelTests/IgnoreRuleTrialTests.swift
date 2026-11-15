import Foundation
import Testing

// The masks of a comparison are internal; a trial promises to match them exactly, which only
// they can show.
@testable import MergeModel

/// Trying a rule on a sample text: the text it leaves out is the text a comparison masks.
struct IgnoreRuleTrialTests {
  @Test func trialFindsTheMatchesOfEachLineAsUTF16Offsets() async {
    let rule = IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#)

    let trial = await rule.trial(on: "é built 2026-11-15\nkept\n😀 2026-01-01", mode: .exact)

    #expect(trial == .matches([8..<18, 27..<37]))
  }

  @Test func anchorsStandForTheStartAndEndOfEachLine() async {
    let rule = IgnoreRule(name: "Last word", pattern: #"\w+$"#)

    #expect(await rule.trial(on: "a b\nc d\n", mode: .exact) == .matches([2..<3, 6..<7]))
  }

  @Test func invalidPatternNamesItsProblem() async {
    #expect(
      await IgnoreRule(name: "", pattern: "(").trial(on: "a", mode: .exact)
        == .problem(.invalidPattern))
    #expect(
      await IgnoreRule(name: "", pattern: ".*").trial(on: "a", mode: .exact)
        == .problem(.matchesEmptyText))
  }

  @Test func lineThatTheModeCountsAsBlankKeepsItsText() async {
    let spaces = IgnoreRule(name: "Spaces", pattern: " +")

    #expect(await spaces.trial(on: "  \na b\n", mode: .exact) == .matches([0..<2, 4..<5]))
    #expect(
      await spaces.trial(on: "  \na b\n", mode: .ignoreWhitespaceAmount) == .matches([4..<5]))
  }

  /// Random texts with every kind of line ending and patterns of several kinds, in every mode:
  /// the trial matches exactly what a comparison of the text masks.
  @Test func trialMatchesWhatAComparisonMasks() async throws {
    let seed: UInt64 = 3131
    var generator = SplitMix64(seed: seed)
    let pieces = ["a", "b1", "22", " ", "\t", "\n", "\r", "\r\n", "é", "😀", "x3y", "0xdeadbeef"]
    let patterns = [#"\d+"#, #"^\w"#, #"\w$"#, #"\s+"#, "[a-z]+", "0x[0-9a-f]{6,}", ".$"]
    for round in 0..<200 {
      let text = (0..<Int.random(in: 0..<30, using: &generator)).map { _ in
        pieces.randomElement(using: &generator) ?? ""
      }.joined()
      let rule = IgnoreRule(
        name: "Rule", pattern: patterns.randomElement(using: &generator) ?? "a")
      for mode in ComparisonMode.allCases {
        let session = try await Session.diff(
          old: SourceFile(bytes: Data(text.utf8), label: "old"),
          new: SourceFile(bytes: Data(), label: "new"), mode: mode, ignoring: [rule])
        let masked = session.files[.a]?.ruleMatches.ranges ?? []
        let trial = await rule.trial(on: text, mode: mode)
        #expect(
          trial == .matches(masked.map { Self.utf16Range(of: $0, in: text) }),
          "Seed \(seed), round \(round), \(mode), \(rule.pattern): \(text.debugDescription)")
      }
    }
  }

  /// The UTF-16 offsets of the UTF-8 offsets `bytes` in `text`.
  private static func utf16Range(of bytes: Range<Int>, in text: String) -> Range<Int> {
    let utf8 = text.utf8
    let start = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
    let end = utf8.index(utf8.startIndex, offsetBy: bytes.upperBound)
    return text.utf16.distance(
      from: text.startIndex, to: start)..<text.utf16.distance(from: text.startIndex, to: end)
  }
}

/// A pattern that backtracks without end, which takes the full time limit to find out.
@Suite(.timeLimit(.minutes(1)))
struct IgnoreRuleTrialTimeLimitTests {
  @Test func trialOfAPatternThatBacktracksWithoutEndEndsWithTheTimeLimit() async {
    let backtracking = IgnoreRule(name: "Backtracking", pattern: #"(a+)+$"#)

    let trial = await backtracking.trial(
      on: String(repeating: "a", count: 40) + "!", mode: .exact)

    #expect(trial == .problem(.exceedsTimeLimit))
  }
}
