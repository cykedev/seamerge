import Foundation
import TextBasics

/// A changed run of a token comparison without the lines that ignore rules match entirely.
///
/// Such a line, its line ending included, is shown as ignored, so it leaves the run, and what
/// is left of each side is highlighted. In ``ComparisonMode/exact``, a line ending counts: where
/// a matched line on one side meets a matched line with another line ending on the other side,
/// the two line endings stay in the run as a change. A run whose sides keep nothing but text
/// that the rules match is no change at all.
struct RuleTrimmedRun {
  /// A range of a run on one side, as absolute bytes, and the whole run on the other side.
  typealias Piece = (own: Range<Int>, other: Range<Int>)

  /// What is left of the run in the first text.
  ///
  /// A side that has nothing left, or had nothing, keeps an empty range at the start of its run,
  /// which marks where the text of the other side is missing.
  let ofFirst: [Piece]

  /// What is left of the run in the second text, like ``ofFirst``.
  let ofSecond: [Piece]

  /// Whether the rules match all that is left of both sides.
  let isMatched: Bool

  /// The number of tokens in what is left of both sides of the run.
  let tokenCount: Int

  /// Trims `run`, whose ranges count from byte `firstStart` of `first` and byte `secondStart`
  /// of `second`, compared in `mode`.
  ///
  /// - Throws: The error of counting the tokens that are left, which takes a comparison.
  init(
    _ run: EngineAdapter.TokenComparison.Run, first: ComparedFile, at firstStart: Int,
    second: ComparedFile, at secondStart: Int, mode: ComparisonMode
  ) throws(MergeModelError) {
    let firstRun = (run.first.lowerBound + firstStart)..<(run.first.upperBound + firstStart)
    let secondRun = (run.second.lowerBound + secondStart)..<(run.second.upperBound + secondStart)
    let firstLines = Self.matchedLines(in: firstRun, of: first)
    let secondLines = Self.matchedLines(in: secondRun, of: second)
    // The matched lines of the two sides pair up in order, as the comparison would pair them.
    var keptEndings = (first: Set<Int>(), second: Set<Int>())
    if mode == .exact {
      for (firstLine, secondLine) in zip(firstLines, secondLines)
      where Self.lineEnding(of: firstLine, in: first) != Self.lineEnding(of: secondLine, in: second)
      {
        keptEndings.first.insert(firstLine)
        keptEndings.second.insert(secondLine)
      }
    }
    let firstPieces = Self.pieces(
      of: firstRun, in: first, without: firstLines, keepingEndingsOf: keptEndings.first)
    let secondPieces = Self.pieces(
      of: secondRun, in: second, without: secondLines, keepingEndingsOf: keptEndings.second)
    isMatched =
      firstPieces.allSatisfy(first.ruleMatches.cover)
      && secondPieces.allSatisfy(second.ruleMatches.cover)
    ofFirst = Self.pieces(firstPieces, of: firstRun, against: secondRun)
    ofSecond = Self.pieces(secondPieces, of: secondRun, against: firstRun)
    // Lines that left the run must not count towards the share of changed tokens, or a few
    // matched lines would hide every highlight of a block.
    if firstPieces == [firstRun] || firstRun.isEmpty,
      secondPieces == [secondRun] || secondRun.isEmpty
    {
      tokenCount = run.tokenCount
    } else {
      tokenCount = try EngineAdapter.compareTokens(
        Self.text(of: firstPieces, in: first), Self.text(of: secondPieces, in: second)
      ).tokenCount
    }
  }

  /// The bytes of `pieces` of `file`, one after the other.
  private static func text(of pieces: [Range<Int>], in file: ComparedFile) -> Data {
    pieces.reduce(into: Data()) { $0.append(file.utf8[$1]) }
  }

  /// `pieces` of `run` with `other`, or an empty range at the start of `run` if none is left.
  private static func pieces(
    _ pieces: [Range<Int>], of run: Range<Int>, against other: Range<Int>
  ) -> [Piece] {
    pieces.isEmpty
      ? [(run.lowerBound..<run.lowerBound, other)] : pieces.map { ($0, other) }
  }

  /// The lines of `file` that `run` touches and that the rules match entirely, in order.
  private static func matchedLines(in run: Range<Int>, of file: ComparedFile) -> [Int] {
    guard !run.isEmpty else { return [] }
    let first = file.line(containingByte: run.lowerBound)
    let last = file.line(containingByte: run.upperBound - 1)
    return (first...last).filter(file.ruleMatches.entireLines.contains)
  }

  /// The line ending of `line`, empty for a last line without one.
  private static func lineEnding(of line: Int, in file: ComparedFile) -> Data {
    file.utf8[file.contentByteRange(ofLine: line).upperBound..<file.lineStarts[line + 1]]
  }

  /// The parts of `run` outside `lines`; a line in `keptEndings` leaves only its content.
  private static func pieces(
    of run: Range<Int>, in file: ComparedFile, without lines: [Int],
    keepingEndingsOf keptEndings: Set<Int>
  ) -> [Range<Int>] {
    guard !run.isEmpty else { return [] }
    var pieces: [Range<Int>] = []
    var start = run.lowerBound
    for line in lines {
      let removed =
        keptEndings.contains(line)
        ? file.contentByteRange(ofLine: line) : file.byteRange(ofLines: line..<line + 1)
      let clamped = removed.clamped(to: run)
      if start < clamped.lowerBound { pieces.append(start..<clamped.lowerBound) }
      start = max(start, clamped.upperBound)
    }
    if start < run.upperBound { pieces.append(start..<run.upperBound) }
    return pieces
  }
}
