import Foundation

/// The lines that differ from the line they are compared with, although the comparison mode
/// counts them as equal: they differ only in whitespace or in their line ending.
///
/// A line is checked against the line it is compared with in its block:
/// - In a merge, A and B against the base where they did not change it, and A against B where
///   both made the same change. Without a base, A is checked against B wherever they are equal.
/// - In a comparison of two files, both files against each other where they are equal.
///
/// With ``ComparisonMode/exact``, lines that count as equal are byte-identical, so there are none.
public struct IgnoredDifferences: Sendable, Hashable {
  /// The differing lines of each input.
  private let linesByRole: [Role: IndexSet]

  /// Each differing line of each input, with the input and the line it is compared with.
  private let pairs: [Role: [LinePair]]

  /// A differing line and the line of another input it is compared with.
  private struct LinePair: Sendable, Hashable {
    var line: Int
    var reference: Role
    var referenceLine: Int
  }

  /// Finds the differing lines in the blocks of `session`.
  ///
  /// The search compares the bytes of every line that counts as equal to another, so it takes
  /// time in proportion to the size of the files; the result is meant to be kept.
  public init(in session: Session) {
    var linesByRole: [Role: IndexSet] = [:]
    var pairs: [Role: [LinePair]] = [:]
    if session.options.mode != .exact {
      let files = session.files
      let hasBase = files[.base] != nil
      for block in session.blocks {
        let comparedRoles = Self.comparedRoles(
          in: block.kind, of: session.kind, hasBase: hasBase)
        for (role, reference) in comparedRoles {
          guard let file = files[role], let referenceFile = files[reference] else { continue }
          for (line, referenceLine) in zip(block.lines(in: role), block.lines(in: reference))
          where !Self.bytesMatch(file, line, referenceFile, referenceLine) {
            linesByRole[role, default: IndexSet()].insert(line)
            pairs[role, default: []].append(
              LinePair(line: line, reference: reference, referenceLine: referenceLine))
          }
        }
      }
    }
    self.linesByRole = linesByRole
    self.pairs = pairs
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
  /// whitespace, widened to whole composed characters.
  ///
  /// A line that differs only in its line ending, or only by lacking whitespace the other line
  /// has, has no place of its own. The search compares the tokens of each differing line, so it
  /// is meant to run once the user asks to see the places; the result is meant to be kept.
  ///
  /// - Precondition: `session` is the session the differences were found in.
  /// - Throws: The error of the comparison.
  public func places(in role: Role, of session: Session) throws(MergeModelError) -> [Place] {
    guard let file = session.files[role] else { return [] }
    var places: [Place] = []
    for pair in (pairs[role] ?? []).sorted(by: { $0.line < $1.line }) {
      guard let referenceFile = session.files[pair.reference] else { continue }
      let text = file.utf8.subdata(in: file.contentByteRange(ofLine: pair.line))
      let referenceText = referenceFile.utf8.subdata(
        in: referenceFile.contentByteRange(ofLine: pair.referenceLine))
      guard text != referenceText else { continue }
      let string = String(decoding: text, as: UTF8.self) as NSString
      for run in try EngineAdapter.compareTokens(text, referenceText).changedRuns
      where !run.first.isEmpty {
        let start = file.lineIndex.utf16Offset(
          ofByteOffset: run.first.lowerBound, inLine: pair.line)
        let end = file.lineIndex.utf16Offset(ofByteOffset: run.first.upperBound, inLine: pair.line)
        let composed = string.rangeOfComposedCharacterSequences(
          for: NSRange(location: start, length: end - start))
        places.append(
          Place(line: pair.line, range: composed.location..<composed.location + composed.length))
      }
    }
    return places
  }

  /// The differing lines of the input of `role`, as zero-based indices.
  public func lines(in role: Role) -> IndexSet {
    linesByRole[role] ?? IndexSet()
  }

  /// Whether no line of any input differs.
  public var isEmpty: Bool { linesByRole.values.allSatisfy(\.isEmpty) }

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
