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

  /// Whether the rules match no text.
  var isEmpty: Bool { ranges.isEmpty }

  /// The matched ranges that overlap `bytes`, in text order.
  func ranges(overlapping bytes: Range<Int>) -> ArraySlice<Range<Int>> {
    var low = 0
    var high = ranges.count
    while low < high {
      let middle = (low + high) / 2
      if ranges[middle].upperBound <= bytes.lowerBound { low = middle + 1 } else { high = middle }
    }
    var end = low
    while end < ranges.count, ranges[end].lowerBound < bytes.upperBound { end += 1 }
    return ranges[low..<end]
  }

  /// Whether the rules match all of `bytes`, which is not empty.
  func cover(_ bytes: Range<Int>) -> Bool {
    ranges(overlapping: bytes).first.map {
      $0.lowerBound <= bytes.lowerBound && bytes.upperBound <= $0.upperBound
    } ?? false
  }
}
