import Foundation

/// The text of a file that the ignore rules of a comparison match.
struct RuleMatches: Sendable {
  /// No match, as in a comparison without rules.
  static let none = RuleMatches(ranges: [], entireLines: IndexSet())

  /// The matched bytes, sorted; each range is non-empty, lies within the content of one line and
  /// neither overlaps nor touches the next.
  let ranges: [Range<Int>]

  /// The lines whose text the rules match entirely, as zero-based indices.
  let entireLines: IndexSet
}
