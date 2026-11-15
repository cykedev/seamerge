import Foundation
import MergeModel
import Testing

struct IgnoreRuleTests {
  static let date = IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#)

  @Test func patternThatCompilesAndNeedsTextIsValid() {
    #expect(Self.date.problem == nil)
    #expect(IgnoreRule(name: "Revision", pattern: #"\$Id:[^$]*\$"#).problem == nil)
  }

  @Test(arguments: ["", "(", "[a-", "a{2,1}", #"\"#, "(?<name"])
  func patternThatDoesNotCompileIsInvalid(pattern: String) {
    #expect(IgnoreRule(name: "Broken", pattern: pattern).problem == .invalidPattern)
  }

  @Test(arguments: [".*", #"\s*"#, "^", "$", "x?", "(abc)*"])
  func patternThatMatchesEmptyTextIsInvalid(pattern: String) {
    #expect(IgnoreRule(name: "Everything", pattern: pattern).problem == .matchesEmptyText)
  }

  @Test func disabledRuleTakesNoEffect() async throws {
    var rule = Self.date
    rule.isEnabled = false

    let session = try await diff("built 2026-01-01\n", "built 2026-11-15\n", ignoring: [rule])

    #expect(session.blocks.map(\.kind) == [.changed])
    #expect(session.ignoreRules.isEmpty)
    #expect(session.ignoreRuleProblems.isEmpty)
  }

  @Test func invalidRuleTakesNoEffectAndNamesItsReason() async throws {
    let broken = IgnoreRule(name: "Broken", pattern: "(")
    let everything = IgnoreRule(name: "Everything", pattern: ".*")

    let session = try await diff(
      "built 2026-01-01\nkept\n", "built 2026-11-15\nchanged\n",
      ignoring: [broken, Self.date, everything])

    #expect(session.ignoreRules == [broken, Self.date, everything])
    #expect(session.ignoreRuleProblems == [broken: .invalidPattern, everything: .matchesEmptyText])
    #expect(session.blocks.map(\.kind) == [.unchanged, .changed])
  }
}

/// Patterns that backtrack without end, which take the full time limit to find out.
@Suite(.timeLimit(.minutes(1)))
struct IgnoreRuleTimeLimitTests {
  @Test func patternThatBacktracksWithoutEndExceedsTheTimeLimitAndTakesNoEffect() async throws {
    let backtracking = IgnoreRule(name: "Backtracking", pattern: #"(a+)+$"#)
    let line = String(repeating: "a", count: 40) + "!\n"

    let clock = ContinuousClock()
    let start = clock.now
    let session = try await diff(
      line + "built 2026-01-01\n", line + "built 2026-11-15\n",
      ignoring: [backtracking, IgnoreRuleTests.date])
    let duration = clock.now - start

    #expect(session.ignoreRuleProblems == [backtracking: .exceedsTimeLimit])
    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(duration < IgnoreRule.timeLimit * 5, "Matching took \(duration)")
  }

  @Test func ruleThatIsTooSlowForOneFileMasksNeither() async throws {
    let backtracking = IgnoreRule(name: "Backtracking", pattern: #"(a+)+$|x\d"#)
    let slowLine = String(repeating: "a", count: 40) + "!\n"

    let session = try await diff("x1\n", slowLine + "x2\n", ignoring: [backtracking])

    #expect(session.ignoreRuleProblems == [backtracking: .exceedsTimeLimit])
    #expect(session.blocks.map(\.kind) == [.changed])
  }
}
