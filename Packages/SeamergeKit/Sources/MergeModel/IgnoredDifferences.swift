public import Foundation
import TextBasics
import TextIO

/// The lines that differ from the line they are compared with, although the comparison counts
/// them as equal: they differ only in whitespace, in their line ending or in text that ignore
/// rules match.
///
/// In a comparison with rules, the lines whose text the rules match entirely and that one side
/// has more count too. Such a line between real changes stays part of the change: it is not
/// one of the differing lines, but its matched text is among the places.
///
/// A line is checked against the line it is compared with in its block:
/// - In a merge, A and B against the base where they did not change it, and A against B where
///   both made the same change. Without a base, A is checked against B wherever they are equal.
/// - In a comparison of two files, both files against each other where they are equal.
///
/// With ``ComparisonMode/exact`` and no rules, lines that count as equal are byte-identical, so
/// there are none.
public struct IgnoredDifferences: Sendable, Hashable {
  /// The differing lines of each input.
  private let linesByRole: [Role: IndexSet]

  /// Each line of each input that has places, with the line of another input it is compared
  /// with.
  private let pairs: [Role: [LinePair]]

  /// A differing line and the line of another input it is compared with, if there is one.
  private struct LinePair: Sendable, Hashable {
    var line: Int
    var reference: Reference?
  }

  /// The line of another input that a line is compared with.
  private struct Reference: Sendable, Hashable {
    var role: Role
    var line: Int
  }

  /// Whether ignore rules pass over at least one of the differences: one that the comparison
  /// mode alone would count.
  ///
  /// Lines that rules match entirely and that one side has more always count; a line compared
  /// with another counts if the rules match text in one of them and the two differ by more than
  /// the mode ignores.
  public let includesDifferencesThatRulesIgnore: Bool

  /// Finds the differing lines in the blocks of `session`.
  ///
  /// The search compares the bytes of every line that counts as equal to another, so it takes
  /// time in proportion to the size of the files; the result is meant to be kept.
  public init(in session: Session) {
    var linesByRole: [Role: IndexSet] = [:]
    var pairs: [Role: [LinePair]] = [:]
    var includesRuleDifferences = false
    let files = session.files
    let hasRules = files.values.contains { !$0.ruleMatches.isEmpty }
    if session.options.mode != .exact || hasRules {
      let hasBase = files[.base] != nil
      for block in session.blocks {
        // A matched line between real changes stays part of the change and gets no ring, but
        // shows its matched text among the places.
        if block.kind == .changed {
          for role in [Role.a, .b] {
            guard let file = files[role] else { continue }
            for line in block.lines(in: role) where file.ruleMatches.entireLines.contains(line) {
              pairs[role, default: []].append(LinePair(line: line, reference: nil))
            }
          }
        }
        let comparedRoles = Self.comparedRoles(
          in: block.kind, of: session.kind, hasBase: hasBase)
        for (role, reference) in comparedRoles {
          guard let file = files[role], let referenceFile = files[reference] else { continue }
          let lines = block.lines(in: role)
          let referenceLines = block.lines(in: reference)
          for (line, referenceLine) in zip(lines, referenceLines)
          where !Self.bytesMatch(file, line, referenceFile, referenceLine) {
            linesByRole[role, default: IndexSet()].insert(line)
            pairs[role, default: []].append(
              LinePair(line: line, reference: Reference(role: reference, line: referenceLine)))
            includesRuleDifferences =
              includesRuleDifferences
              || Self.rulesHide(
                line, of: file, from: referenceLine, of: referenceFile, mode: session.options.mode)
          }
          // Only lines that rules match entirely stand alone in an unchanged block.
          for line in lines.dropFirst(referenceLines.count) {
            linesByRole[role, default: IndexSet()].insert(line)
            pairs[role, default: []].append(LinePair(line: line, reference: nil))
            includesRuleDifferences = true
          }
        }
      }
    }
    self.linesByRole = linesByRole
    self.pairs = pairs
    includesDifferencesThatRulesIgnore = includesRuleDifferences
  }

  /// A place within a line where it differs from the line it is compared with.
  public struct Place: Sendable, Hashable {
    /// The zero-based index of the line.
    public var line: Int

    /// The characters of the place, as UTF-16 offsets from the start of the line.
    public var range: Range<Int>

    /// Creates the place of the characters `range` of `line`.
    public init(line: Int, range: Range<Int>) {
      self.line = line
      self.range = range
    }
  }

  /// The places where the differing lines of the input of `role` differ, in line order: the
  /// characters a line has in place of those of the line it is compared with, such as other
  /// whitespace, and the text that ignore rules match in it where it differs, widened to whole
  /// composed characters and joined where they overlap.
  ///
  /// A line without a line it is compared with, such as a line that the rules match entirely,
  /// has the text that the rules match as its places. A line that differs only in its line
  /// ending, or only by lacking text the other line has, has no place of its own. The search
  /// compares the tokens of each differing line, so it is meant to run once the user asks to see
  /// the places; the result is meant to be kept.
  ///
  /// - Precondition: `session` is the session the differences were found in.
  /// - Throws: The error of the comparison.
  public func places(in role: Role, of session: Session) throws(MergeModelError) -> [Place] {
    guard let file = session.files[role] else { return [] }
    var places: [Place] = []
    for pair in (pairs[role] ?? []).sorted(by: { $0.line < $1.line }) {
      let content = file.contentByteRange(ofLine: pair.line)
      let lineStart = file.lineStarts[pair.line]
      let matched = file.ruleMatches.ranges(overlapping: content).map {
        ($0.lowerBound - lineStart)..<($0.upperBound - lineStart)
      }
      var byteRanges = matched
      if let reference = pair.reference, let referenceFile = session.files[reference.role] {
        let text = file.utf8.subdata(in: content)
        let referenceText = referenceFile.utf8.subdata(
          in: referenceFile.contentByteRange(ofLine: reference.line))
        let runs =
          text == referenceText
          ? [] : try EngineAdapter.compareTokens(text, referenceText).changedRuns.map(\.first)
        // Matched text counts only where text of this line differs within it, as one place.
        byteRanges =
          runs.filter { !$0.isEmpty }
          + matched.filter { range in runs.contains { !$0.isEmpty && range.overlaps($0) } }
      }
      let string = String(decoding: file.utf8.subdata(in: content), as: UTF8.self) as NSString
      var lineRanges: [Range<Int>] = []
      for bytes in byteRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        let start = file.lineIndex.utf16Offset(ofByteOffset: bytes.lowerBound, inLine: pair.line)
        let end = file.lineIndex.utf16Offset(ofByteOffset: bytes.upperBound, inLine: pair.line)
        let composed = string.rangeOfComposedCharacterSequences(
          for: NSRange(location: start, length: end - start))
        let range = composed.location..<composed.location + composed.length
        if let last = lineRanges.last, range.lowerBound <= last.upperBound {
          lineRanges[lineRanges.count - 1] =
            last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
          lineRanges.append(range)
        }
      }
      places += lineRanges.map { Place(line: pair.line, range: $0) }
    }
    return places
  }

  /// The differing lines of the input of `role`, as zero-based indices.
  public func lines(in role: Role) -> IndexSet {
    linesByRole[role] ?? IndexSet()
  }

  /// Whether no line of any input differs and no line within a change has places.
  public var isEmpty: Bool { pairs.values.allSatisfy(\.isEmpty) }

  /// The inputs whose lines are checked in a block of `kind`, each with the input it is checked
  /// against.
  private static func comparedRoles(
    in kind: Block.Kind, of sessionKind: Session.Kind, hasBase: Bool
  ) -> [(role: Role, reference: Role)] {
    switch (sessionKind, kind) {
    case (.diff, .unchanged): [(.a, .b), (.b, .a)]
    case (.merge, .unchanged) where hasBase: [(.a, .base), (.b, .base)]
    case (.merge, .unchanged), (.merge, .changedInBoth): [(.a, .b)]
    case (.merge, .changedInA): [(.b, .base)]
    case (.merge, .changedInB): [(.a, .base)]
    case (_, .conflict), (_, .changed), (.diff, _): []
    }
  }

  /// Whether ignore rules match text in `line` or `referenceLine` and the two lines differ by
  /// more than the comparison mode ignores.
  private static func rulesHide(
    _ line: Int, of file: ComparedFile, from referenceLine: Int, of referenceFile: ComparedFile,
    mode: ComparisonMode
  ) -> Bool {
    let hasMatches = [(file, line), (referenceFile, referenceLine)].contains { file, line in
      !file.ruleMatches.ranges(overlapping: file.contentByteRange(ofLine: line)).isEmpty
    }
    return hasMatches
      && MoveDetection.fingerprint(ofLine: line, in: file.text, mode: mode)
        != MoveDetection.fingerprint(ofLine: referenceLine, in: referenceFile.text, mode: mode)
  }

  /// Whether two lines have the same bytes, line endings included.
  private static func bytesMatch(
    _ file: ComparedFile, _ line: Int, _ otherFile: ComparedFile, _ otherLine: Int
  ) -> Bool {
    let range = file.byteRange(ofLines: line..<line + 1)
    let otherRange = otherFile.byteRange(ofLines: otherLine..<otherLine + 1)
    guard range.count == otherRange.count else { return false }
    return file.utf8.withUnsafeBytes { bytes in
      otherFile.utf8.withUnsafeBytes { otherBytes in
        bytes[range].elementsEqual(otherBytes[otherRange])
      }
    }
  }
}
