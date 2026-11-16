import Foundation

/// The text that a search over several panes goes through: the searchable pieces of their lines,
/// one after the other in the order the owner of the panes gave, as one long string.
///
/// Each piece is a line of a pane, or the piece of a line beside a preview. Filler rows, previews
/// and empty lines have no piece. A line feed stands between every two pieces, of one pane or of
/// two, so that no match reaches from one line into the next or from one pane into the next:
/// neither a text that the user types into the search field nor a pattern such as any character
/// matches it, and a word ends there as at the end of a line. A match that holds one all the
/// same, for a search for a line break or for text of several lines, belongs to no pane.
///
/// The text is a snapshot: a string of its own, put together from the panes' texts, which never
/// changes and can be read from any thread.
struct SearchText: Sendable {
  /// A searchable piece of a line: where it starts in the search text, which pane it belongs to,
  /// and where it lies in that pane's text, all in UTF-16 code units.
  struct Piece: Sendable, Equatable {
    var start: Int
    var pane: Int
    var offset: Int
    var length: Int

    /// The range of the piece in the search text.
    var range: Range<Int> { start..<start + length }

    /// The range of the piece in its pane's text.
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

  /// The search text itself, which the finder reads.
  let string: String

  /// The pieces, in the order of the search text.
  let pieces: [Piece]

  /// For each pane, the indices of its pieces in the order of its text.
  private let piecesByPane: [[Int]]

  /// The length of the search text.
  let length: Int

  /// A search text without pieces.
  static let empty = SearchText(texts: [], sections: [])

  /// Puts together the search text of `sections` of panes whose texts are `texts`.
  ///
  /// - Precondition: The lines and excluded ranges of each section lie within the text of its
  ///   pane, and the lines are sorted and apart.
  init(texts: [String], sections: [Section]) {
    var pieces: [Piece] = []
    var start = 0
    func append(pane: Int, offset: Int, length: Int) {
      if !pieces.isEmpty {
        // The line feed before the piece.
        start += 1
      }
      pieces.append(Piece(start: start, pane: pane, offset: offset, length: length))
      start += length
    }
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
            append(pane: section.pane, offset: position, length: gap.lowerBound - position)
          }
          position = max(position, gap.upperBound)
        }
        if position < line.upperBound {
          append(pane: section.pane, offset: position, length: line.upperBound - position)
        }
      }
    }
    var piecesByPane = Array(repeating: [Int](), count: texts.count)
    for (index, piece) in pieces.enumerated() {
      piecesByPane[piece.pane].append(index)
    }
    // The sections of a pane usually come in the order of its rows already.
    for pane in piecesByPane.indices
    where !zip(piecesByPane[pane], piecesByPane[pane].dropFirst()).allSatisfy({
      pieces[$0].offset < pieces[$1].offset
    }) {
      piecesByPane[pane].sort { pieces[$0].offset < pieces[$1].offset }
    }
    self.pieces = pieces
    // The line feeds first, then the pieces between them.
    var characters = [unichar](repeating: 0x0A, count: start)
    characters.withUnsafeMutableBufferPointer { buffer in
      // An empty text has no characters to copy.
      guard let base = buffer.baseAddress else { return }
      let texts = texts.map { $0 as NSString }
      for piece in pieces {
        texts[piece.pane].getCharacters(base + piece.start, range: NSRange(piece.paneRange))
      }
    }
    string = String(decoding: characters, as: UTF16.self)
    self.piecesByPane = piecesByPane
    self.length = start
  }

  /// The pane and the range in its text of `range` of the search text, or `nil` if the range
  /// does not lie within one piece, as a range that holds a line feed between two pieces.
  ///
  /// An empty range at the end of a piece lies in that piece.
  func paneRange(of range: Range<Int>) -> (pane: Int, range: Range<Int>)? {
    let index =
      range.isEmpty
      ? pieces.partitioningIndex { $0.range.upperBound >= range.lowerBound }
      : pieces.partitioningIndex { $0.range.upperBound > range.lowerBound }
    guard index < pieces.count else { return nil }
    let piece = pieces[index]
    guard piece.start <= range.lowerBound, range.upperBound <= piece.range.upperBound else {
      return nil
    }
    let start = piece.offset + range.lowerBound - piece.start
    return (piece.pane, start..<start + range.count)
  }

  /// The range of the search text at `range` of the text of `pane`.
  ///
  /// A range that starts outside every piece, on a filler row, a line feed or a preview, becomes
  /// an empty range at the start of the next piece of the pane, or at the end of its last one;
  /// one that reaches beyond its piece ends with the piece.
  func searchRange(ofPaneRange range: Range<Int>, inPane pane: Int) -> Range<Int>? {
    guard piecesByPane.indices.contains(pane), let last = piecesByPane[pane].last else {
      return nil
    }
    let indices = piecesByPane[pane]
    let next = indices.partitioningIndex { pieces[$0].paneRange.upperBound > range.lowerBound }
    guard next < indices.count else {
      let end = pieces[last].range.upperBound
      return end..<end
    }
    let piece = pieces[indices[next]]
    guard piece.offset <= range.lowerBound else { return piece.start..<piece.start }
    let start = piece.start + range.lowerBound - piece.offset
    return start..<min(start + range.count, piece.range.upperBound)
  }

  /// The longest range of the search text around `index` whose pieces all belong to the same
  /// pane, or `nil` if the index lies at or beyond the end; an index on a line feed counts with
  /// the piece after it.
  func paneStretch(containing index: Int) -> (pane: Int, range: Range<Int>)? {
    guard index >= 0, index < length else { return nil }
    let found = pieces.partitioningIndex { $0.range.upperBound > index }
    guard found < pieces.count else { return nil }
    let pane = pieces[found].pane
    var first = found
    while first > 0, pieces[first - 1].pane == pane {
      first -= 1
    }
    var last = found
    while last + 1 < pieces.count, pieces[last + 1].pane == pane {
      last += 1
    }
    return (pane, pieces[first].start..<pieces[last].range.upperBound)
  }

  /// The ranges of the search text that lie within `range` of the text of `pane`, one for each
  /// piece they touch, in the order of the search text.
  func searchRanges(within range: Range<Int>, ofPane pane: Int) -> [Range<Int>] {
    guard piecesByPane.indices.contains(pane) else { return [] }
    let indices = piecesByPane[pane]
    var first = indices.partitioningIndex {
      pieces[$0].paneRange.upperBound > range.lowerBound
    }
    var ranges: [Range<Int>] = []
    while first < indices.count, pieces[indices[first]].offset < range.upperBound {
      let piece = pieces[indices[first]]
      let start = max(piece.offset, range.lowerBound)
      let end = min(piece.paneRange.upperBound, range.upperBound)
      ranges.append(piece.start + start - piece.offset..<piece.start + end - piece.offset)
      first += 1
    }
    return ranges.sorted { $0.lowerBound < $1.lowerBound }
  }
}
