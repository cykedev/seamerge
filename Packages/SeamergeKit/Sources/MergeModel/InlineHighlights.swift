import Foundation

/// The characters of a block that changed, and the places where a side removed text, for the
/// stronger tint and the removal marks within lines.
///
/// The text of a block is compared as a whole, in runs of one character class, with the text it
/// changed: in a merge, A and B each with the base. Without a base, in a merge as in a comparison
/// of two files, A and B are compared with each other and both are highlighted. The base pane
/// stays without highlights, and so does a side that did not change the block. A merge with a
/// base can also compare A with B, as panes that show it without its base do: then both sides
/// are highlighted where they differ, whichever changed the block, and a block in which both
/// made the same change has no highlights. Changes that the comparison mode ignores are not
/// highlighted, nor are lines that ignore rules match entirely and runs of text that the rules
/// match on both sides. When more than 60 % of the runs of a comparison changed, removed runs
/// included, it highlights nothing, because the block as a whole is then the change; nor does a
/// comparison in which the text of the block is larger than 64 KiB in one of the two inputs, such
/// as thousands of lines replaced at once, whose comparison would hold up the window.
///
/// A run that one side replaced is highlighted on both sides. A run that one side lacks is
/// highlighted on the side that has it and marked by an empty range on the side that lacks it,
/// unless it consists of whole lines: those already show as rows the other side does not have.
public struct InlineHighlights: Sendable, Hashable {
  /// The highlighted ranges of each pane.
  private let rangesByRole: [Role: [Range<Int>]]

  /// The highlights of the pane of `role`, as UTF-16 ranges in its ``DisplayText/string``.
  ///
  /// The ranges are sorted, do not overlap and never split a composed character. A change that
  /// spans several lines is highlighted per line, without the line endings.
  ///
  /// An empty range marks a place where the side lacks text that the other side has. It lies at
  /// the start of a composed character or at the end of a line, and at most once per removal: a
  /// removal that spans line breaks of the other side is marked once, where the text is missing.
  public func ranges(in role: Role) -> [Range<Int>] {
    rangesByRole[role] ?? []
  }

  /// Whether no pane has a highlight or a removal mark.
  public var isEmpty: Bool { rangesByRole.values.allSatisfy(\.isEmpty) }

  /// The share of changed runs above which a comparison highlights nothing: three fifths.
  private static let maximumChangedShare = (numerator: 3, denominator: 5)

  /// The most UTF-8 bytes that the text of a block may take in each of the two inputs of a
  /// comparison for the comparison to highlight it.
  private static let maximumBlockSize = 65_536

  /// Compares the texts of `block` in `session`: A with B if `comparingSides` or the session
  /// has no base, and each side with the base otherwise.
  init(block: Block, in session: Session, comparingSides: Bool = false) throws(MergeModelError) {
    var rangesByRole: [Role: [Range<Int>]] = [:]
    let comparisons = Self.comparisons(
      for: block.kind, hasBase: session.files[.base] != nil, comparingSides: comparingSides)
    for comparison in comparisons {
      guard let firstFile = session.files[comparison.first],
        let secondFile = session.files[comparison.second]
      else { continue }
      let firstBytes = firstFile.byteRange(ofLines: block.lines(in: comparison.first))
      let secondBytes = secondFile.byteRange(ofLines: block.lines(in: comparison.second))
      guard
        firstBytes.count <= Self.maximumBlockSize && secondBytes.count <= Self.maximumBlockSize
      else { continue }
      let firstText = firstFile.utf8.subdata(in: firstBytes)
      let secondText = secondFile.utf8.subdata(in: secondBytes)
      let tokens = try EngineAdapter.compareTokens(firstText, secondText)
      let filter = ChangeFilter(mode: session.options.mode, first: firstText, second: secondText)
      var runs: [RuleTrimmedRun] = []
      for run in tokens.changedRuns where !filter.ignores(run) {
        runs.append(
          try RuleTrimmedRun(
            run, first: firstFile, at: firstBytes.lowerBound, second: secondFile,
            at: secondBytes.lowerBound, mode: session.options.mode))
      }
      let shownRuns = runs.filter { !$0.isMatched }
      let changedTokenCount = shownRuns.reduce(0) { $0 + $1.tokenCount }
      guard
        changedTokenCount * Self.maximumChangedShare.denominator
          <= tokens.tokenCount * Self.maximumChangedShare.numerator
      else { continue }
      if comparison.highlightsFirst {
        rangesByRole[comparison.first] = Self.displayRanges(
          of: shownRuns.flatMap(\.ofFirst), in: firstFile, against: secondFile,
          role: comparison.first, layout: session.rowLayout)
      }
      rangesByRole[comparison.second] = Self.displayRanges(
        of: shownRuns.flatMap(\.ofSecond), in: secondFile, against: firstFile,
        role: comparison.second, layout: session.rowLayout)
    }
    self.rangesByRole = rangesByRole.filter { !$0.value.isEmpty }
  }

  /// A comparison of the texts of two inputs in a block.
  private struct Comparison {
    /// The input the second one is compared with.
    var first: Role

    /// The input whose changes are highlighted.
    var second: Role

    /// Whether the changes are highlighted in the first input too.
    var highlightsFirst: Bool
  }

  /// The comparisons that highlight a block of `kind` in a session with or without a base, or
  /// that compare A with B in a session with a base if `comparingSides`.
  private static func comparisons(
    for kind: Block.Kind, hasBase: Bool, comparingSides: Bool
  ) -> [Comparison] {
    guard kind != .unchanged else { return [] }
    let sides = Comparison(first: .a, second: .b, highlightsFirst: true)
    guard hasBase else { return [sides] }
    if comparingSides {
      return kind == .changedInBoth ? [] : [sides]
    }
    let a = Comparison(first: .base, second: .a, highlightsFirst: false)
    let b = Comparison(first: .base, second: .b, highlightsFirst: false)
    return switch kind {
    case .changedInA: [a]
    case .changedInB: [b]
    case .changedInBoth, .conflict: [a, b]
    case .unchanged, .changed: []
    }
  }

  /// Converts changed runs into UTF-16 ranges in the pane of `file`: a run `file` has into
  /// highlights, one per line and without line endings, widened to whole composed characters;
  /// a run only `other` has into a removal mark.
  ///
  /// - Parameter runs: The byte ranges of each run in `file` and in `other`, in text order.
  /// - Precondition: Every range starts and ends at the start of a Unicode scalar.
  private static func displayRanges(
    of runs: [(own: Range<Int>, other: Range<Int>)], in file: ComparedFile,
    against other: ComparedFile, role: Role, layout: RowLayout
  ) -> [Range<Int>] {
    guard let displayText = layout.displayText(for: role) else { return [] }
    let string = displayText.string as NSString
    var offsets = UTF16Offsets(file: file)
    var ranges: [Range<Int>] = []
    for run in runs {
      if run.own.isEmpty {
        if let mark = removalMark(
          at: run.own.lowerBound, removing: run.other, in: file, against: other,
          displayText: displayText, role: role, layout: layout)
        {
          insert(mark, into: &ranges)
        }
        continue
      }
      var line = file.line(containingByte: run.own.lowerBound)
      while line < file.lineCount, file.lineStarts[line] < run.own.upperBound {
        let content = file.contentByteRange(ofLine: line)
        let lower = max(run.own.lowerBound, content.lowerBound) - content.lowerBound
        let upper = min(run.own.upperBound, content.upperBound) - content.lowerBound
        if lower < upper {
          let rowStart = displayText.utf16Range(ofRow: layout.row(ofLine: line, in: role))
            .lowerBound
          let start = rowStart + offsets.offset(ofByte: lower, inLine: line)
          let end = rowStart + offsets.offset(ofByte: upper, inLine: line)
          let composed = string.rangeOfComposedCharacterSequences(
            for: NSRange(location: start, length: end - start))
          // The line feed before a row joins a combining mark at the start of the row into one
          // character, which must not pull the highlight out of its row.
          insert(
            max(composed.location, rowStart)..<(composed.location + composed.length),
            into: &ranges)
        }
        line += 1
      }
    }
    return ranges
  }

  /// The empty range in the pane of `file` that marks the place `offset` where `file` lacks the
  /// bytes `removed` of `other`, or `nil` when they are whole lines.
  ///
  /// Whole lines run from the start of a line to the start of another, or from the end of the
  /// content of a line to the end of the content of another. Any other removal leaves a line
  /// on this side with something missing: text within a line, at its start or end, or a line
  /// break that joined two lines. Such a removal is marked once at `offset`, even when `removed`
  /// spans line breaks, because the place where it is missing is a single one.
  private static func removalMark(
    at offset: Int, removing removed: Range<Int>, in file: ComparedFile,
    against other: ComparedFile, displayText: DisplayText, role: Role, layout: RowLayout
  ) -> Range<Int>? {
    let isWholeLines =
      (other.startsLine(at: removed.lowerBound) && other.startsLine(at: removed.upperBound))
      || (other.endsLineContent(at: removed.lowerBound)
        && other.endsLineContent(at: removed.upperBound))
    guard !isWholeLines, file.lineCount > 0 else { return nil }
    // A removal that is not whole lines follows a token this side shares, so `offset` lies within
    // a line or at the end of the last one, never after the final line ending.
    let line = offset < file.utf8.count ? file.line(containingByte: offset) : file.lineCount - 1
    let rowStart = displayText.utf16Range(ofRow: layout.row(ofLine: line, in: role)).lowerBound
    var position =
      rowStart
      + file.lineIndex.utf16Offset(ofByteOffset: offset - file.lineStarts[line], inLine: line)
    let string = displayText.string as NSString
    if position < string.length {
      // As in `displayRanges`, a combining mark at the start of the row must not move the mark
      // to the line feed before it.
      position = max(rowStart, string.rangeOfComposedCharacterSequence(at: position).location)
    }
    return position..<position
  }

  /// Appends `range` to the sorted `ranges`, joining it with the ranges it overlaps or touches.
  ///
  /// A removal mark that touches a highlight is absorbed by it, and a second mark at the same
  /// place is dropped, so every place is marked once.
  private static func insert(_ range: Range<Int>, into ranges: inout [Range<Int>]) {
    var joined = range
    while let last = ranges.last,
      last.lowerBound <= joined.upperBound, joined.lowerBound <= last.upperBound
    {
      joined = min(last.lowerBound, joined.lowerBound)..<max(last.upperBound, joined.upperBound)
      ranges.removeLast()
    }
    ranges.append(joined)
  }
}

/// Converts byte offsets within the lines of a file into UTF-16 offsets, going on from the
/// offset it converted last where that lies before in the same line.
///
/// The runs of a line come in text order, so the runs of a long line take time in proportion to
/// the line rather than to the line times the number of runs.
private struct UTF16Offsets {
  let file: ComparedFile
  private var last: (line: Int, byte: Int, utf16: Int)?

  init(file: ComparedFile) {
    self.file = file
  }

  /// The UTF-16 offset from the start of `line` that corresponds to the byte offset `byte` from
  /// its start.
  ///
  /// - Precondition: `byte` lies within the line or at its end, at the start of a Unicode scalar.
  mutating func offset(ofByte byte: Int, inLine line: Int) -> Int {
    guard let last, last.line == line, last.byte <= byte else {
      let utf16 = file.lineIndex.utf16Offset(ofByteOffset: byte, inLine: line)
      self.last = (line, byte, utf16)
      return utf16
    }
    let start = file.lineStarts[line]
    let utf16 = file.utf8.withUnsafeBytes { bytes in
      var count = last.utf16
      for index in (start + last.byte)..<(start + byte) where !UTF8.isContinuation(bytes[index]) {
        // A scalar of four bytes lies outside the Basic Multilingual Plane and takes two units.
        count += bytes[index] >= 0xF0 ? 2 : 1
      }
      return count
    }
    self.last = (line, byte, utf16)
    return utf16
  }
}

extension Session {
  /// Compares the texts of a block within lines.
  ///
  /// The comparison takes time in proportion to the size of the block, so it is meant for the
  /// blocks on screen; the result is meant to be kept.
  ///
  /// - Parameter comparingSides: Whether A is compared with B rather than each side with the
  ///   base, for panes that show a merge without its base; without a base, A and B are compared
  ///   anyway.
  /// - Precondition: `block` is one of ``blocks``.
  /// - Throws: The error of the comparison.
  public func inlineHighlights(
    for block: Block, comparingSides: Bool = false
  ) throws(MergeModelError) -> InlineHighlights {
    precondition(blocks.indices.contains(block.id), "Block \(block.id) is not in the session")
    return try InlineHighlights(block: block, in: self, comparingSides: comparingSides)
  }
}

extension Range<Int> {
  /// The range moved by `offset`.
  fileprivate func shifted(by offset: Int) -> Range<Int> {
    (lowerBound + offset)..<(upperBound + offset)
  }
}
