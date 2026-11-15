import Foundation
import PaneKit

/// The comparison of the base of a sample merge with B in a single column, the way the merge model
/// lays it out: the lines both files share once with both numbers, and in each changed block the
/// lines of the base above those of B, each part tinted and marked as its pane side by side.
struct SingleColumnSample {
  /// The content of the pane.
  let content: PaneContent

  /// The marks of the overview bar, one for each part of each block, one below the other.
  let overviewMarks: [OverviewMark]

  /// For each block, the rows of its upper and its lower part, either of which may be empty.
  let parts: [(upper: Range<Int>, lower: Range<Int>)]

  /// Lays out the comparison of the base of `merge` with B; the marks of the overview bar cover
  /// the leading two thirds of the bar for the base and the trailing two thirds for B.
  init(_ merge: SampleMerge) {
    var rows: [String] = []
    var left: [Int32] = []
    var right: [Int32] = []
    var blocks: [PaneBlock] = []
    var marks: [OverviewMark] = []
    var parts: [(upper: Range<Int>, lower: Range<Int>)] = []
    var nextLine = (left: Int32(0), right: Int32(0))
    func append(_ lines: [String], toLeft: Bool, toRight: Bool) {
      for line in lines {
        left.append(toLeft ? nextLine.left : -1)
        right.append(toRight ? nextLine.right : -1)
        nextLine.left += toLeft ? 1 : 0
        nextLine.right += toRight ? 1 : 0
        rows.append(line)
      }
    }
    func change(_ old: [String], _ new: [String]) {
      let start = rows.count
      append(old, toLeft: true, toRight: false)
      let middle = rows.count
      append(new, toLeft: false, toRight: true)
      let block = blocks.count
      let upper = start..<middle
      let lower = middle..<rows.count
      parts.append((upper, lower))
      let both = !old.isEmpty && !new.isEmpty
      if old.isEmpty {
        blocks.append(PaneBlock(rows: lower, style: .tinted(.b), marker: .added))
      } else {
        blocks.append(
          PaneBlock(
            rows: start..<rows.count, style: .tinted(.a), marker: both ? .changed : .removed,
            lowerPart: both
              ? PaneBlockPart(firstRow: middle, style: .tinted(.b), marker: .changed) : nil))
      }
      for (part, role) in [(upper, ColorRole.a), (lower, .b)] where !part.isEmpty {
        marks.append(
          OverviewMark(
            rows: part, style: .tinted(role),
            placement: role == .a ? .leading : .trailing,
            block: block, accessibilityLabel: role == .a ? "Removed" : "Added"))
      }
    }
    for chunk in merge.chunks {
      switch chunk {
      case .same(let lines):
        append(lines, toLeft: true, toRight: true)
      case .onlyA(_, let base, _):
        append(base, toLeft: true, toRight: true)
      case .onlyB(let base, let b, _), .both(_, let base, let b, _):
        change(base, b)
      case .conflict(_, let base, let b, _, _):
        change(base, b)
      }
    }
    content = PaneContent(
      text: rows.joined(separator: "\n"), lineNumbers: rows.indices.map { Int32($0) },
      sideLineNumbers: SideLineNumbers(left: left, right: right), blocks: blocks)
    overviewMarks = marks
    self.parts = parts
  }
}

/// Highlights, between the two parts of each block of a single column, the run of each line
/// between the prefix and the suffix that it shares with the line at the same place in the other
/// part.
@MainActor
final class SingleColumnHighlights: PaneHighlightProvider {
  private let sample: SingleColumnSample

  init(_ sample: SingleColumnSample) {
    self.sample = sample
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    let lines = sample.content.text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { Array($0.utf16) }
    var starts: [Int] = []
    var offset = 0
    for line in lines {
      starts.append(offset)
      offset += line.count + 1
    }
    let (upper, lower) = sample.parts[block]
    var ranges: [Range<Int>] = []
    for (own, other) in [(upper, lower), (lower, upper)] {
      for (row, otherRow) in zip(own, other) {
        let (line, reference) = (lines[row], lines[otherRow])
        var suffix = 0
        while suffix < min(line.count, reference.count)
          && line[line.count - 1 - suffix] == reference[reference.count - 1 - suffix]
        {
          suffix += 1
        }
        var prefix = 0
        while prefix < min(line.count, reference.count) - suffix
          && line[prefix] == reference[prefix]
        {
          prefix += 1
        }
        if prefix + suffix < line.count {
          ranges.append(starts[row] + prefix..<starts[row] + line.count - suffix)
        }
      }
    }
    return ranges.sorted { $0.lowerBound < $1.lowerBound }
  }
}
