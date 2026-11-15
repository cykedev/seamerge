import Foundation

/// The text that a search over several panes goes through: the searchable parts of their lines,
/// one after the other in the order the owner of the panes gave, as one long string that never
/// holds a line feed.
///
/// Each part is a line of a pane, or the piece of a line beside a preview, and ends with a search
/// boundary, so that no match reaches from one line or pane into the next. Filler rows, previews
/// and empty lines have no part. The text is a snapshot: it holds copies of the panes' texts and
/// can be read from any thread, as the find bar reads it while it searches as the user types.
struct SearchText: Sendable {
  /// A searchable part of a line: where it starts in the search text, which pane it belongs to,
  /// and where it lies in that pane's text, all in UTF-16 code units.
  struct Part: Sendable, Equatable {
    var start: Int
    var pane: Int
    var offset: Int
    var length: Int

    /// The range of the part in the search text.
    var range: Range<Int> { start..<start + length }

    /// The range of the part in its pane's text.
    var paneRange: Range<Int> { offset..<offset + length }
  }

  /// A piece of a pane's text that the search goes through: some of its rows, given with their
  /// text and the parts of the text left out.
  struct Section: Sendable {
    /// The index of the pane among the panes of the search.
    var pane: Int
    /// The range in the pane's text of each row of the section, without its line feed, in order;
    /// filler rows are left out.
    var lines: [Range<Int>]
    /// The ranges of the pane's text that are never searched, sorted and apart.
    var excluded: [Range<Int>]
  }

  /// The text of each pane, by the index of the pane.
  private let texts: [String]

  /// The parts, in the order of the search text.
  let parts: [Part]

  /// For each pane, the indices of its parts in the order of its text.
  private let partsByPane: [[Int]]

  /// The length of the search text.
  let length: Int

  /// A search text without parts.
  static let empty = SearchText(texts: [], sections: [])

  /// Puts together the search text of `sections` of panes whose texts are `texts`.
  ///
  /// - Precondition: The lines and excluded ranges of each section lie within the text of its
  ///   pane, and the lines are sorted and apart.
  init(texts: [String], sections: [Section]) {
    self.texts = texts
    var parts: [Part] = []
    var start = 0
    for section in sections {
      var excluded = section.excluded[...]
      for line in section.lines {
        var position = line.lowerBound
        // Ranges that end before the line cannot touch it or any line after it.
        while let first = excluded.first, first.upperBound <= position {
          excluded.removeFirst()
        }
        for gap in excluded {
          guard gap.lowerBound < line.upperBound else { break }
          if position < gap.lowerBound {
            parts.append(
              Part(
                start: start, pane: section.pane, offset: position,
                length: gap.lowerBound - position))
            start += gap.lowerBound - position
          }
          position = max(position, gap.upperBound)
        }
        if position < line.upperBound {
          parts.append(
            Part(
              start: start, pane: section.pane, offset: position,
              length: line.upperBound - position))
          start += line.upperBound - position
        }
      }
    }
    var partsByPane = Array(repeating: [Int](), count: texts.count)
    for (index, part) in parts.enumerated() {
      partsByPane[part.pane].append(index)
    }
    // The sections of a pane usually come in the order of its rows already.
    for pane in partsByPane.indices
    where !zip(partsByPane[pane], partsByPane[pane].dropFirst()).allSatisfy({
      parts[$0].offset < parts[$1].offset
    }) {
      partsByPane[pane].sort { parts[$0].offset < parts[$1].offset }
    }
    self.parts = parts
    self.partsByPane = partsByPane
    self.length = start
  }

  /// The index of the part that holds the character at `index` of the search text, or `nil` if
  /// the index lies at or beyond the end.
  func partIndex(containing index: Int) -> Int? {
    guard index >= 0, index < length else { return nil }
    return parts.partitioningIndex { $0.start + $0.length > index }
  }

  /// The text of the part at `partIndex`.
  func text(ofPart partIndex: Int) -> String {
    let part = parts[partIndex]
    return (texts[part.pane] as NSString).substring(with: NSRange(part.paneRange))
  }

  /// The pane and the range in its text of `range` of the search text, or `nil` if the range
  /// does not lie within one part.
  ///
  /// An empty range at the end of a part lies in that part.
  func paneRange(of range: Range<Int>) -> (pane: Int, range: Range<Int>)? {
    // An empty range at the end of a part belongs to that part.
    let index = range.isEmpty ? max(range.lowerBound - 1, 0) : range.lowerBound
    guard let index = partIndex(containing: index) else { return nil }
    let part = parts[index]
    guard part.range.lowerBound <= range.lowerBound, range.upperBound <= part.range.upperBound
    else { return nil }
    let start = part.offset + range.lowerBound - part.start
    return (part.pane, start..<start + range.count)
  }

  /// The range of the search text at `range` of the text of `pane`.
  ///
  /// A range that starts outside every part, on a filler row, a line feed or a preview, becomes
  /// an empty range at the start of the next part of the pane, or at the end of its last one;
  /// one that reaches beyond its part ends with the part.
  func searchRange(ofPaneRange range: Range<Int>, inPane pane: Int) -> Range<Int>? {
    guard partsByPane.indices.contains(pane), let last = partsByPane[pane].last else {
      return nil
    }
    let indices = partsByPane[pane]
    let next = indices.partitioningIndex { parts[$0].offset + parts[$0].length > range.lowerBound }
    guard next < indices.count else {
      let end = parts[last].start + parts[last].length
      return end..<end
    }
    let part = parts[indices[next]]
    guard part.offset <= range.lowerBound else { return part.start..<part.start }
    let start = part.start + range.lowerBound - part.offset
    return start..<min(start + range.count, part.start + part.length)
  }

  /// The longest range of the search text around `index` whose parts all belong to the same
  /// pane, or `nil` if the index lies at or beyond the end.
  func paneStretch(containing index: Int) -> (pane: Int, range: Range<Int>)? {
    guard let found = partIndex(containing: index) else { return nil }
    let pane = parts[found].pane
    var first = found
    while first > 0, parts[first - 1].pane == pane {
      first -= 1
    }
    var last = found
    while last + 1 < parts.count, parts[last + 1].pane == pane {
      last += 1
    }
    return (pane, parts[first].start..<parts[last].start + parts[last].length)
  }

  /// The ranges of the search text that lie within `range` of the text of `pane`, one for each
  /// part they touch, in the order of the search text.
  func searchRanges(within range: Range<Int>, ofPane pane: Int) -> [Range<Int>] {
    guard partsByPane.indices.contains(pane) else { return [] }
    let indices = partsByPane[pane]
    var first = indices.partitioningIndex {
      parts[$0].offset + parts[$0].length > range.lowerBound
    }
    var ranges: [Range<Int>] = []
    while first < indices.count, parts[indices[first]].offset < range.upperBound {
      let part = parts[indices[first]]
      let start = max(part.offset, range.lowerBound)
      let end = min(part.offset + part.length, range.upperBound)
      ranges.append(part.start + start - part.offset..<part.start + end - part.offset)
      first += 1
    }
    return ranges.sorted { $0.lowerBound < $1.lowerBound }
  }
}
