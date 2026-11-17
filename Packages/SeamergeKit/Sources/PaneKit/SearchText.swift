import Foundation

/// The text that a search over several panes goes through: the searchable pieces of their text,
/// one after the other in the order the owner of the panes gave, as one long string.
///
/// Each piece is a run of lines of a pane that follow each other in its text, with the line feeds
/// between them, or the part of such a run beside a preview. Filler rows and previews have no
/// piece, and empty lines start or end none. A line feed stands between every two pieces, of one
/// pane or of two, so that the search text holds a line feed wherever a line ends: no match of a
/// text without one reaches from one line into the next, from one section into the next or from
/// one pane into the next, and a word ends there as at the end of a line. A match that holds a
/// line feed all the same, for text of several lines, belongs to no pane.
///
/// The text is a snapshot: a string of its own, copied from the panes' texts, which never changes
/// and can be read from any thread. It keeps the characters in UTF-16, as the panes do, so that
/// it takes a copy of their characters and nothing more to make, and the finder reads it without
/// converting.
struct SearchText: Sendable {
  /// A searchable piece of the text: where it starts in the search text, which pane it belongs
  /// to, and where it lies in that pane's text, all in UTF-16 code units.
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
  ///   pane, the lines are sorted and apart, and each line that follows another right after its
  ///   line feed starts one character after the end of that line.
  init(texts: [NSString], sections: [Section]) {
    var runs = Runs()
    for section in sections {
      var excluded = section.excluded[...]
      for line in section.lines {
        // Ranges that end before the line cannot touch it or any line after it.
        while let first = excluded.first, first.upperBound <= line.lowerBound {
          excluded.removeFirst()
        }
        var position = line.lowerBound
        for gap in excluded {
          guard gap.lowerBound < line.upperBound else { break }
          if position < gap.lowerBound {
            runs.add(
              position..<gap.lowerBound, of: section.pane, startsLine: position == line.lowerBound,
              endsLine: false)
          }
          position = max(position, gap.upperBound)
        }
        if position < line.upperBound || position == line.lowerBound {
          runs.add(
            position..<line.upperBound, of: section.pane,
            startsLine: position == line.lowerBound, endsLine: true)
        }
      }
    }
    runs.end()
    let pieces = runs.pieces
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
    let length = pieces.last?.range.upperBound ?? 0
    // The line feeds between the pieces first, then the pieces between them.
    var characters = [unichar](repeating: 0x0A, count: length)
    characters.withUnsafeMutableBufferPointer { buffer in
      // An empty text has no characters to copy.
      guard let base = buffer.baseAddress else { return }
      for piece in pieces {
        texts[piece.pane].getCharacters(base + piece.start, range: NSRange(piece.paneRange))
      }
    }
    self.pieces = pieces
    self.piecesByPane = piecesByPane
    self.length = length
    string = NSString(characters: characters, length: length) as String
  }

  /// Gathers the lines of the sections into pieces: lines of a pane that follow each other in
  /// its text go into one piece, and empty lines start or end none.
  private struct Runs {
    /// A run of lines under way.
    private struct Run {
      /// The pane of the lines.
      var pane: Int

      /// The range of the run in the pane's text, from the start of its first line that is not
      /// empty to the end of its last one.
      var range: Range<Int>

      /// The end of the last line the run reaches, which a line must follow right after its line
      /// feed to join it; `nil` once a preview has cut the run short.
      var reach: Int?
    }

    /// The pieces so far, in the order of the search text.
    private(set) var pieces: [Piece] = []

    /// The run under way, if any.
    private var run: Run?

    /// Adds `part` of a line of `pane`: the whole line or the part of it beside a preview.
    mutating func add(_ part: Range<Int>, of pane: Int, startsLine: Bool, endsLine: Bool) {
      let reach = endsLine ? part.upperBound : nil
      guard var current = run, current.pane == pane, startsLine,
        let end = current.reach, part.lowerBound == end + 1
      else {
        self.end()
        run = Run(pane: pane, range: part, reach: reach)
        return
      }
      if current.range.isEmpty {
        // Empty lines before it start no piece.
        current = Run(pane: pane, range: part, reach: reach)
      } else {
        // An empty line joins the run, but only a line after it that is not empty extends it.
        if !part.isEmpty {
          current.range = current.range.lowerBound..<part.upperBound
        }
        current.reach = reach
      }
      run = current
    }

    /// Ends the run under way, which becomes a piece unless it is empty.
    mutating func end() {
      defer { run = nil }
      guard let run, !run.range.isEmpty else { return }
      // A line feed stands before every piece but the first.
      let start = pieces.last.map { $0.range.upperBound + 1 } ?? 0
      pieces.append(
        Piece(
          start: start, pane: run.pane, offset: run.range.lowerBound, length: run.range.count))
    }
  }

  /// The pane and the range in its text of `range` of the search text, or `nil` if the range
  /// does not lie within one line of one piece, as a range that holds a line feed.
  ///
  /// An empty range at the end of a piece lies in that piece.
  func paneRange(of range: Range<Int>) -> (pane: Int, range: Range<Int>)? {
    let index =
      range.isEmpty
      ? pieces.partitioningIndex { $0.range.upperBound >= range.lowerBound }
      : pieces.partitioningIndex { $0.range.upperBound > range.lowerBound }
    guard index < pieces.count else { return nil }
    let piece = pieces[index]
    guard piece.start <= range.lowerBound, range.upperBound <= piece.range.upperBound,
      !holdsLineFeed(range)
    else { return nil }
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

  /// Whether `range` of the search text holds a line feed.
  private func holdsLineFeed(_ range: Range<Int>) -> Bool {
    (string as NSString).range(of: "\n", options: .literal, range: NSRange(range)).location
      != NSNotFound
  }
}
