import Foundation
import Testing

@testable import MergeEngine

/// Compares exact-mode merges with `git merge-file`. Differences are expected
/// in places and are recorded here rather than hidden; a change in either
/// tool shows up as a failing expectation.
@Suite("Comparison with git merge-file", .enabled(if: GitMergeFile.isAvailable))
struct GitComparisonTests {
  enum Agreement: String, CaseIterable, Sendable {
    /// Both merge cleanly to the same bytes.
    case sameResult
    /// Both merge cleanly to different bytes.
    case differentResult
    /// Perforce merges cleanly, git reports a conflict.
    case onlyGitConflicts
    /// Git merges cleanly, Perforce reports a conflict.
    case onlyPerforceConflicts
    /// Both report conflicts. The texts are not compared: the tools delimit
    /// conflicts differently (see the README's "Behavior").
    case bothConflict
  }

  static let expectedAgreement: [String: Agreement] = [
    "merge-adjacent": .onlyGitConflicts,
    "merge-clean": .sameResult,
    "merge-conflict": .bothConflict,
    "merge-crlf": .bothConflict,
    "merge-delete": .sameResult,
    "merge-delete-vs-edit": .bothConflict,
    "merge-empty-all": .sameResult,
    "merge-empty-base": .sameResult,
    "merge-empty-both-add": .bothConflict,
    "merge-insert-same-place": .bothConflict,
    "merge-missing-final-newline": .onlyGitConflicts,
    "merge-missing-final-newline-conflict": .bothConflict,
    "merge-nonutf8": .sameResult,
    "merge-same-change": .sameResult,
    "merge-split-conflict": .bothConflict,
    "merge-whitespace-edit": .bothConflict,
    "merge-whitespace-vs-edit": .bothConflict,
  ]

  private func agreement(base: Data, a: Data, b: Data) throws -> Agreement {
    let perforce = try Merge(base: base, a: a, b: b)
    let git = try GitMergeFile.merge(base: base, a: a, b: b)
    switch (perforce.hasConflicts, git.conflictCount > 0) {
    case (false, false): return perforce.result()?.data == git.text ? .sameResult : .differentResult
    case (false, true): return .onlyGitConflicts
    case (true, false): return .onlyPerforceConflicts
    case (true, true): return .bothConflict
    }
  }

  @Test("Every merge fixture has a recorded agreement")
  func everyFixtureIsRecorded() {
    #expect(Set(Fixtures.mergeCases) == Set(Self.expectedAgreement.keys))
  }

  @Test("Fixtures agree with git as recorded", arguments: Fixtures.mergeCases)
  func fixture(name: String) throws {
    let input = try Fixtures.triple(name)
    #expect(try agreement(base: input.base, a: input.a, b: input.b) == Self.expectedAgreement[name])
  }

  @Test("Conflict markers are the same as git's", arguments: [Merge.ConflictStyle.merge, .diff3])
  func conflictMarkers(style: Merge.ConflictStyle) throws {
    let input = try Fixtures.triple("merge-conflict")
    let merge = try Merge(base: input.base, a: input.a, b: input.b)
    let git = try GitMergeFile.merge(
      base: input.base, a: input.a, b: input.b, diff3: style == .diff3)
    #expect(merge.result(markingConflicts: style).data == git.text)
  }

  /// Where both tools merge cleanly, they must produce the same text. The
  /// other outcomes are tallied and attached to the test run.
  @Test("Clean merges of random input match git")
  func randomMerges() throws {
    var generator = SplitMix64(seed: 2026)
    var tally: [Agreement: Int] = [:]
    var examples: [Agreement: String] = [:]

    for _ in 0..<400 {
      let input = RandomMergeInput(using: &generator)
      let outcome = try agreement(base: input.base, a: input.a, b: input.b)
      tally[outcome, default: 0] += 1
      if examples[outcome] == nil { examples[outcome] = input.description }
    }

    #expect(tally[.differentResult] == nil, "\(examples[.differentResult] ?? "")")

    let report = Agreement.allCases.map { agreement in
      "\(agreement.rawValue): \(tally[agreement] ?? 0)"
        + (examples[agreement].map { "\n  first: \($0)" } ?? "")
    }.joined(separator: "\n")
    Attachment.record(report, named: "git-merge-file-agreement.txt")
  }
}
