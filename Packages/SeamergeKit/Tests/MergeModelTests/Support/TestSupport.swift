import Foundation
import MergeModel
import Testing

extension SourceFile {
  /// A file with `text` as its UTF-8 content.
  init(_ text: String, label: String = "file") {
    self.init(bytes: Data(text.utf8), label: label)
  }
}

/// Merges three texts.
func merge(
  base: String?, a: String, b: String, mode: ComparisonMode = .exact
) async throws -> Session {
  try await Session.merge(
    base: base.map { SourceFile($0, label: "base") }, a: SourceFile(a, label: "a"),
    b: SourceFile(b, label: "b"), options: ComparisonOptions(mode: mode))
}

/// Compares two texts.
func diff(_ old: String, _ new: String, mode: ComparisonMode = .exact) async throws -> Session {
  try await Session.diff(
    old: SourceFile(old, label: "old"), new: SourceFile(new, label: "new"), mode: mode)
}

extension Session {
  /// The display text of `role`, which the test expects to exist.
  func displayString(of role: Role) throws -> String {
    try #require(rowLayout.displayText(for: role)).string
  }

  /// The text of each row of the pane of `role`.
  func rowTexts(of role: Role) throws -> [String] {
    let text = try #require(rowLayout.displayText(for: role))
    return (0..<text.rowCount).map { text.string.utf16Substring(text.utf16Range(ofRow: $0)) }
  }

  /// The highlighted texts in the pane of `role` for the first block of `kind`, without the
  /// removal marks.
  func highlightedTexts(of role: Role, inFirst kind: Block.Kind) throws -> [String] {
    let string = try displayString(of: role)
    return try inlineRanges(of: role, inFirst: kind).filter { !$0.isEmpty }
      .map { string.utf16Substring($0) }
  }

  /// The UTF-16 positions of the removal marks in the pane of `role` for the first block of
  /// `kind`.
  func removalMarks(of role: Role, inFirst kind: Block.Kind) throws -> [Int] {
    try inlineRanges(of: role, inFirst: kind).filter(\.isEmpty).map(\.lowerBound)
  }

  /// The inline ranges, highlights and removal marks, in the pane of `role` for the first block
  /// of `kind`.
  func inlineRanges(of role: Role, inFirst kind: Block.Kind) throws -> [Range<Int>] {
    let block = try #require(blocks.first { $0.kind == kind })
    return try inlineHighlights(for: block).ranges(in: role)
  }
}

extension String {
  /// The text of a UTF-16 range.
  func utf16Substring(_ range: Range<Int>) -> String {
    (self as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
  }
}
