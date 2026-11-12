import Foundation

/// The characters of a block that changed, for the stronger tint within lines.
///
/// The text of a block is compared as a whole, in runs of one character class, with the text it
/// changed: in a merge, A and B each with the base. Without a base, in a merge as in a comparison
/// of two files, A and B are compared with each other and both are highlighted. The base pane
/// stays without highlights, and so does a side that did not change the block. Changes that the
/// comparison mode ignores are not highlighted. When more than 60 % of the runs of a comparison
/// changed, it highlights nothing, because the block as a whole is then the change.
public struct InlineHighlights: Sendable, Hashable {
  /// The highlighted ranges of each pane.
  private let rangesByRole: [Role: [Range<Int>]]

  /// The highlights of the pane of `role`, as UTF-16 ranges in its ``DisplayText/string``.
  ///
  /// The ranges are sorted, do not overlap and never split a composed character. A change that
  /// spans several lines is highlighted per line, without the line endings.
  public func ranges(in role: Role) -> [Range<Int>] {
    rangesByRole[role] ?? []
  }

  /// Whether no pane has a highlight.
  public var isEmpty: Bool { rangesByRole.values.allSatisfy(\.isEmpty) }

  /// The share of changed runs above which a comparison highlights nothing: three fifths.
  private static let maximumChangedShare = (numerator: 3, denominator: 5)

  /// Compares the texts of `block` in `session`.
  init(block: Block, in session: Session) throws(MergeModelError) {
    var rangesByRole: [Role: [Range<Int>]] = [:]
    let comparisons = Self.comparisons(for: block.kind, hasBase: session.files[.base] != nil)
    for comparison in comparisons {
      guard let firstFile = session.files[comparison.first],
        let secondFile = session.files[comparison.second]
      else { continue }
      let firstBytes = firstFile.byteRange(ofLines: block.lines(in: comparison.first))
      let secondBytes = secondFile.byteRange(ofLines: block.lines(in: comparison.second))
      let firstText = firstFile.utf8.subdata(in: firstBytes)
      let secondText = secondFile.utf8.subdata(in: secondBytes)
      let tokens = try EngineAdapter.compareTokens(firstText, secondText)
      let filter = ChangeFilter(mode: session.options.mode, first: firstText, second: secondText)
      let shownRuns = tokens.changedRuns.filter { !filter.ignores($0) }
      let changedTokenCount = shownRuns.reduce(0) { $0 + $1.tokenCount }
      guard
        changedTokenCount * Self.maximumChangedShare.denominator
          <= tokens.tokenCount * Self.maximumChangedShare.numerator
      else { continue }
      if comparison.highlightsFirst {
        rangesByRole[comparison.first] = Self.displayRanges(
          ofBytes: shownRuns.map { $0.first.shifted(by: firstBytes.lowerBound) },
          in: firstFile, role: comparison.first, layout: session.rowLayout)
      }
      rangesByRole[comparison.second] = Self.displayRanges(
        ofBytes: shownRuns.map { $0.second.shifted(by: secondBytes.lowerBound) },
        in: secondFile, role: comparison.second, layout: session.rowLayout)
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

  /// The comparisons that highlight a block of `kind` in a session with or without a base.
  private static func comparisons(for kind: Block.Kind, hasBase: Bool) -> [Comparison] {
    guard kind != .unchanged else { return [] }
    guard hasBase else { return [Comparison(first: .a, second: .b, highlightsFirst: true)] }
    let a = Comparison(first: .base, second: .a, highlightsFirst: false)
    let b = Comparison(first: .base, second: .b, highlightsFirst: false)
    return switch kind {
    case .changedInA: [a]
    case .changedInB: [b]
    case .changedInBoth, .conflict: [a, b]
    case .unchanged, .changed: []
    }
  }

  /// Converts byte ranges in the text of a file into UTF-16 ranges in its pane, one per line
  /// and without line endings, widened to whole composed characters.
  ///
  /// - Precondition: Every range starts and ends at the start of a Unicode scalar.
  private static func displayRanges(
    ofBytes byteRanges: [Range<Int>], in file: ComparedFile, role: Role, layout: RowLayout
  ) -> [Range<Int>] {
    guard let displayText = layout.displayText(for: role) else { return [] }
    let string = displayText.string as NSString
    var ranges: [Range<Int>] = []
    for byteRange in byteRanges where !byteRange.isEmpty {
      var line = file.line(containingByte: byteRange.lowerBound)
      while line < file.lineCount, file.lineStarts[line] < byteRange.upperBound {
        let content = file.contentByteRange(ofLine: line)
        let lower = max(byteRange.lowerBound, content.lowerBound) - content.lowerBound
        let upper = min(byteRange.upperBound, content.upperBound) - content.lowerBound
        if lower < upper {
          let rowStart = displayText.utf16Range(ofRow: layout.row(ofLine: line, in: role))
            .lowerBound
          let start = rowStart + file.lineIndex.utf16Offset(ofByteOffset: lower, inLine: line)
          let end = rowStart + file.lineIndex.utf16Offset(ofByteOffset: upper, inLine: line)
          let composed = string.rangeOfComposedCharacterSequences(
            for: NSRange(location: start, length: end - start))
          let range = composed.location..<(composed.location + composed.length)
          if let last = ranges.last, range.lowerBound <= last.upperBound {
            ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
          } else {
            ranges.append(range)
          }
        }
        line += 1
      }
    }
    return ranges
  }
}

extension Session {
  /// Compares the texts of a block within lines.
  ///
  /// The comparison takes time in proportion to the size of the block, so it is meant for the
  /// blocks on screen; the result is meant to be kept.
  ///
  /// - Precondition: `block` is one of ``blocks``.
  /// - Throws: The error of the comparison.
  public func inlineHighlights(for block: Block) throws(MergeModelError) -> InlineHighlights {
    precondition(blocks.indices.contains(block.id), "Block \(block.id) is not in the session")
    return try InlineHighlights(block: block, in: self)
  }
}

extension Range<Int> {
  /// The range moved by `offset`.
  fileprivate func shifted(by offset: Int) -> Range<Int> {
    (lowerBound + offset)..<(upperBound + offset)
  }
}
