import PaneKit

/// Highlights, in each line of a block, the run between the suffix and the prefix that the line
/// shares with the same line of another pane on the same grid; where the line only lost text, an
/// empty run marks the place.
///
/// That is cruder than the comparison of the engine, but enough to show what highlights look like.
@MainActor
final class SampleHighlights: PaneHighlightProvider {
  private let content: PaneContent
  private let reference: PaneContent?

  /// Highlights `content` against `reference`, or not at all if there is none.
  init(content: PaneContent, reference: PaneContent?) {
    self.content = content
    self.reference = reference
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    let rows = content.blocks[block].rows
    guard let reference else { return [] }
    let ownLines = lines(of: content)
    let referenceLines = lines(of: reference)
    let rowStarts = starts(of: ownLines)
    return rows.compactMap { row in
      guard content.lineNumbers[row] >= 0, reference.lineNumbers[row] >= 0 else { return nil }
      let own = Array(ownLines[row].utf16)
      let other = Array(referenceLines[row].utf16)
      // The common end first: where a side inserted text that starts like the text after it,
      // as "Unicode.UTF8" against "UTF8", the run then lies before the shared text.
      var suffix = 0
      while suffix < min(own.count, other.count)
        && own[own.count - 1 - suffix] == other[other.count - 1 - suffix]
      {
        suffix += 1
      }
      var prefix = 0
      while prefix < min(own.count, other.count) - suffix && own[prefix] == other[prefix] {
        prefix += 1
      }
      guard prefix + suffix < own.count else {
        // The line only lost text: an empty run marks the place.
        return prefix + suffix < other.count
          ? rowStarts[row] + prefix..<rowStarts[row] + prefix : nil
      }
      return rowStarts[row] + prefix..<rowStarts[row] + own.count - suffix
    }
  }

  private func lines(of content: PaneContent) -> [String] {
    content.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  private func starts(of lines: [String]) -> [Int] {
    var starts: [Int] = []
    var offset = 0
    for line in lines {
      starts.append(offset)
      offset += line.utf16.count + 1
    }
    return starts
  }
}
