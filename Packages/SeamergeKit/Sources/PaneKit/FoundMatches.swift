import Foundation

/// The matches of a search, placed in their panes: each with its pane, its range in the pane's
/// text and its row, in the order of the search, and the ranges of each pane in the order of
/// its text.
struct FoundMatches: Sendable {
  /// A match in its pane, by the pane's index among the panes of the search.
  struct Place: Sendable {
    var pane: Int
    var range: Range<Int>
    var row: Int
  }

  /// The matches, in the order of the search.
  var places: [Place] = []

  /// The ranges of the matches of each pane, sorted and apart.
  var rangesByPane: [[Range<Int>]] = []

  /// The rows of each pane that matches start in.
  var rowsByPane: [IndexSet] = []

  /// No matches.
  static let none = FoundMatches()

  /// Places `ranges`, the matches the finder found in `text`, in the panes whose rows `grids`
  /// give, away from the main actor; a range that lies in no pane, as across two lines, is
  /// left out.
  @concurrent
  static func placing(
    _ ranges: [Range<Int>], in text: SearchText, grids: [RowGrid]
  ) async -> FoundMatches {
    var found = FoundMatches(
      rangesByPane: Array(repeating: [], count: grids.count),
      rowsByPane: Array(repeating: [], count: grids.count))
    found.places.reserveCapacity(ranges.count)
    for range in ranges {
      guard let place = text.paneRange(of: range), grids.indices.contains(place.pane) else {
        continue
      }
      let row = grids[place.pane].row(containingOffset: place.range.lowerBound)
      found.places.append(Place(pane: place.pane, range: place.range, row: row))
      found.rangesByPane[place.pane].append(place.range)
      found.rowsByPane[place.pane].insert(row)
    }
    // The finder finds the matches in the order of the search text, whose pieces follow the
    // panes' texts unless the sections of a pane come out of order.
    for pane in found.rangesByPane.indices
    where !zip(found.rangesByPane[pane], found.rangesByPane[pane].dropFirst()).allSatisfy({
      $0.lowerBound < $1.lowerBound
    }) {
      found.rangesByPane[pane].sort { $0.lowerBound < $1.lowerBound }
    }
    return found
  }
}
