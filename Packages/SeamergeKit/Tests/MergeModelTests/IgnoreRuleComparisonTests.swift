import Foundation
import MergeModel
import Testing

struct IgnoreRuleComparisonTests {
  static let date = IgnoreRule(name: "Build date", pattern: #"\d{4}-\d{2}-\d{2}"#)
  static let digits = IgnoreRule(name: "Digits", pattern: #"\d+"#)

  @Test(arguments: ComparisonMode.allCases)
  func linesThatDifferOnlyInMatchedTextAreEqual(mode: ComparisonMode) async throws {
    let session = try await diff(
      "// built 2026-01-01\nlet x = 1\n", "// built 2026-11-15\nlet x = 1\n", mode: mode,
      ignoring: [Self.date])

    #expect(session.blocks.map(\.kind) == [.unchanged])
    #expect(session.ignoreRules == [Self.date])
    #expect(session.ignoreRuleProblems.isEmpty)
  }

  @Test func differenceOutsideTheMatchedTextStillCounts() async throws {
    let session = try await diff(
      "// built 2026-01-01 by ci\n", "// built 2026-11-15 by me\n", ignoring: [Self.date])

    #expect(session.blocks.map(\.kind) == [.changed])
  }

  @Test func matchesOfSeveralRulesAllDropOut() async throws {
    let version = IgnoreRule(name: "Version", pattern: #"v\d+\.\d+"#)

    let session = try await diff(
      "v1.2 built 2026-01-01\n", "v1.3 built 2026-11-15\n", ignoring: [Self.date, version])

    #expect(session.blocks.map(\.kind) == [.unchanged])
  }

  @Test func anchorsStandForTheStartAndEndOfEachLine() async throws {
    let trailing = IgnoreRule(name: "Trailing number", pattern: #"\d+$"#)
    let comment = IgnoreRule(name: "Comment line", pattern: "^#.*")

    let session = try await diff(
      "a1\n#one\nb2\nc #x\n", "a3\n#two\nb4\nc #y\n", ignoring: [trailing, comment])

    #expect(session.blocks.map(\.kind) == [.unchanged, .changed])
    #expect(session.blocks.last?.a == 3..<4)
  }

  @Test func matchNeverReachesPastTheEndOfALine() async throws {
    let acrossLines = IgnoreRule(name: "Across lines", pattern: #"[a-d]x\s+y[a-d]"#)

    let session = try await diff("ax\nyb\n", "cx\nyd\n", ignoring: [acrossLines])

    #expect(session.blocks.map(\.kind) == [.changed])
  }

  @Test(arguments: ComparisonMode.allCases)
  func filesWithLinesThatEndInCarriageReturnsStayLineForLine(mode: ComparisonMode) async throws {
    let session = try await diff(
      "a 1\rb 2\rc 3\r", "a 9\rb 8\rX\r", mode: mode, ignoring: [Self.digits])

    #expect(try session.lineTexts(of: .a) == ["a 1", "b 2", "c 3"])
    #expect(try session.lineTexts(of: .b) == ["a 9", "b 8", "X"])
    #expect(session.blocks.map(\.kind) == [.unchanged, .changed])
    #expect(session.blocks.first?.a == 0..<2)
  }

  @Test(arguments: ComparisonMode.allCases)
  func lineThatRulesEmptyAfterALoneCarriageReturnStaysALineOfItsOwn(mode: ComparisonMode)
    async throws
  {
    let session = try await diff(
      "a\r2026-01-01\nz\n", "a\r2026-11-15\nz\n", mode: mode, ignoring: [Self.date])

    let lineCount = mode == .exact ? 2 : 3
    #expect(session.rowLayout.lineCount(in: .a) == lineCount)
    #expect(session.rowLayout.lineCount(in: .b) == lineCount)
    #expect(session.blocks.map(\.kind) == [.unchanged])
  }

  @Test(arguments: ComparisonMode.allCases)
  func shownTextIsTheTextOfTheFile(mode: ComparisonMode) async throws {
    let old = "Grüße 😀 2026-01-01\r\nlet x = 1\n\tcafé 2026-01-02\rend"
    let new = "Grüße 😀 2026-11-15\r\nlet x = 2\n\tcafé 2026-11-16\rend"

    let session = try await diff(old, new, mode: mode, ignoring: [Self.date])
    let unmasked = try await diff(old, new, mode: mode)

    for (role, text, date) in [(Role.a, old, "2026-01-01"), (.b, new, "2026-11-15")] {
      #expect(session.inputs[role]?.bytes == Data(text.utf8))
      #expect(try session.lineTexts(of: role) == unmasked.lineTexts(of: role))
      #expect(try session.lineTexts(of: role).first == "Grüße 😀 \(date)")
      #expect(try !session.displayString(of: role).contains("\u{FFFD}"))
    }
  }

  @Test func otherComparisonModeKeepsTheRules() async throws {
    let session = try await diff(
      "built 2026-01-01\n", "built  2026-11-15\n", ignoring: [Self.date])
    #expect(session.blocks.map(\.kind) == [.changed])

    let switched = try await session.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))

    #expect(switched.ignoreRules == [Self.date])
    #expect(switched.blocks.map(\.kind) == [.unchanged])
  }

  @Test func rulesSwitchOnAndOffLikeAComparisonMode() async throws {
    let session = try await diff("built 2026-01-01\n", "built 2026-11-15\n")
    #expect(session.blocks.map(\.kind) == [.changed])

    let withRules = try await session.recomputed(ignoring: [Self.date])
    #expect(withRules.blocks.map(\.kind) == [.unchanged])

    let withoutRules = try await withRules.recomputed(ignoring: [])
    #expect(withoutRules.blocks.map(\.kind) == [.changed])
    #expect(withoutRules.ignoreRules.isEmpty)
  }

  @Test func mergeComparesAllText() async throws {
    let session = try await merge(
      base: "built 2026-01-01\n", a: "built 2026-11-15\n", b: "built 2026-01-01\n")

    #expect(session.blocks.map(\.kind) == [.changedInA])
    #expect(session.ignoreRules.isEmpty)
    let switched = try await session.recomputed(
      options: ComparisonOptions(mode: .ignoreWhitespaceAmount))
    #expect(switched.blocks.map(\.kind) == [.changedInA])
  }

  @Test func movedLinesAreFoundWithoutTheMatchedText() async throws {
    let moved = "// stamped 2026-01-01\nfunc moved() {\n  return compute(42) // 2026-01-01\n}\n"
    let stamped = moved.replacing("2026-01-01", with: "2026-11-15")
    let rest = "func kept() {\n  let first = 1\n  let second = 2\n  return first + second\n}\n"

    let without = try await diff(moved + rest, rest + stamped)
    let with = try await diff(moved + rest, rest + stamped, ignoring: [Self.date])

    #expect(without.moves.isEmpty)
    #expect(with.moves.map { [$0.source.lines, $0.destination.lines] } == [[0..<4, 5..<9]])
  }

  /// Random texts with every kind of line ending, compared with a rule in every mode: the lines
  /// of the files are the lines the engine finds in them without rules.
  @Test func linesOfTheFilesAreTheLinesTheEngineFindsInEveryMode() async throws {
    let seed: UInt64 = 27
    var generator = SplitMix64(seed: seed)
    let pieces = ["a", "b1", "22", " ", "\t", "\n", "\r", "\r\n", "é", "😀", "x3y"]
    for round in 0..<300 {
      let texts = (0..<2).map { _ in
        (0..<Int.random(in: 0..<30, using: &generator)).map { _ in
          pieces.randomElement(using: &generator) ?? ""
        }.joined()
      }
      for mode in ComparisonMode.allCases {
        let masked = try await diff(texts[0], texts[1], mode: mode, ignoring: [Self.digits])
        let unmasked = try await diff(texts[0], texts[1], mode: mode)
        for role in [Role.a, .b] {
          #expect(
            try masked.lineTexts(of: role) == unmasked.lineTexts(of: role),
            "Seed \(seed), round \(round), \(mode), \(role): \(texts.map(\.debugDescription))")
        }
      }
    }
  }

  /// Random texts compared with patterns that could see past a line, each against the same
  /// pattern in a group: the group changes nothing about what the pattern matches, so both
  /// comparisons have the same blocks and the same places of ignored differences.
  @Test func patternMatchesTheSameAsItsGroupedForm() async throws {
    let seed: UInt64 = 1227
    var generator = SplitMix64(seed: seed)
    let patterns = [
      #"\d+"#, #"^\w"#, #"\w$"#, #"\s+"#, #"a\s*b"#, #"[^a]+"#, ".$", "^.", #"b\b"#, #"\bx"#,
      #"(a|b)\1"#, #"\R"#, #"x[\s\S]y"#,
    ]
    let pieces = [
      "a", "b", "x", "y", "1", " ", "\t", "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "é",
    ]
    for round in 0..<200 {
      let old = (0..<Int.random(in: 0..<24, using: &generator)).map { _ in
        pieces.randomElement(using: &generator) ?? ""
      }.joined()
      var new = Array(old)
      for _ in 0..<Int.random(in: 0..<4, using: &generator) where !new.isEmpty {
        new[Int.random(in: 0..<new.count, using: &generator)] =
          pieces.randomElement(using: &generator)?.first ?? "a"
      }
      let pattern = patterns.randomElement(using: &generator) ?? ""
      let mode = ComparisonMode.allCases.randomElement(using: &generator) ?? .exact
      let plain = try await diff(
        old, String(new), mode: mode, ignoring: [IgnoreRule(name: "Plain", pattern: pattern)])
      let grouped = try await diff(
        old, String(new), mode: mode,
        ignoring: [IgnoreRule(name: "Grouped", pattern: "(?:\(pattern))")])
      let context = "Seed \(seed), round \(round), \(mode), \(pattern): \(old.debugDescription)"
      #expect(plain.blocks == grouped.blocks, "\(context)")
      let plainDifferences = IgnoredDifferences(in: plain)
      let groupedDifferences = IgnoredDifferences(in: grouped)
      for role in [Role.a, .b] {
        #expect(
          try plainDifferences.places(in: role, of: plain)
            == groupedDifferences.places(in: role, of: grouped), "\(context)")
      }
    }
  }
}
