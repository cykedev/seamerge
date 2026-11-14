/// The rows of a grid that wrap onto more than one screen line, each with its number of lines;
/// every other row takes one.
///
/// Most rows of code fit the width of a pane, so the rows are kept only where they wrap.
struct WrappedRows: Equatable, Sendable {
  /// A row that takes more than one screen line.
  struct Entry: Equatable, Sendable {
    /// The row of the grid.
    var row: Int
    /// The number of screen lines the row takes, more than one.
    var lines: Int
  }

  /// The rows that wrap, in row order.
  private(set) var entries: [Entry]

  /// No row wraps.
  static let none = WrappedRows([])

  /// Keeps `entries`.
  ///
  /// - Precondition: The entries are sorted by row, each row at most once, each with more than
  ///   one line.
  init(_ entries: [Entry]) {
    precondition(
      zip(entries, entries.dropFirst()).allSatisfy { $0.row < $1.row }
        && entries.allSatisfy { $0.lines > 1 },
      "Wrapped rows must be sorted, distinct and take more than one line")
    self.entries = entries
  }

  /// Whether no row wraps.
  var isEmpty: Bool { entries.isEmpty }

  /// The number of screen lines that `row` takes.
  func lines(ofRow row: Int) -> Int {
    let index = entries.partitioningIndex { $0.row >= row }
    return index < entries.count && entries[index].row == row ? entries[index].lines : 1
  }

  /// The rows of both, each with the larger number of lines.
  func merged(with other: WrappedRows) -> WrappedRows {
    var merged: [Entry] = []
    merged.reserveCapacity(entries.count + other.entries.count)
    var (left, right) = (entries[...], other.entries[...])
    while let first = left.first, let second = right.first {
      if first.row == second.row {
        merged.append(Entry(row: first.row, lines: max(first.lines, second.lines)))
        left.removeFirst()
        right.removeFirst()
      } else if first.row < second.row {
        merged.append(first)
        left.removeFirst()
      } else {
        merged.append(second)
        right.removeFirst()
      }
    }
    merged += left
    merged += right
    return WrappedRows(merged)
  }

  /// The first row that takes another number of screen lines here than in `other`, or `nil` if
  /// every row takes as many in both.
  func firstRow(differingFrom other: WrappedRows) -> Int? {
    for (own, others) in zip(entries, other.entries) where own != others {
      return min(own.row, others.row)
    }
    let (shorter, longer) =
      entries.count < other.entries.count ? (entries, other.entries) : (other.entries, entries)
    return longer.count > shorter.count ? longer[shorter.count].row : nil
  }

  /// The rows below `rowCount`.
  func clamped(toRowCount rowCount: Int) -> WrappedRows {
    guard let last = entries.last, last.row >= rowCount else { return self }
    return WrappedRows(Array(entries[..<entries.partitioningIndex { $0.row >= rowCount }]))
  }

  /// Takes over an edit that rewrote rows as `change` says: the rows before keep their lines,
  /// those after move with the rows, and the rewritten rows take `rewritten`.
  ///
  /// - Precondition: `rewritten` lies within the new rows of `change`, sorted.
  mutating func takeOver(_ change: RowChange, rewritten: [Entry]) {
    let start = entries.partitioningIndex { $0.row >= change.oldRows.lowerBound }
    let end = entries.partitioningIndex { $0.row >= change.oldRows.upperBound }
    let delta = change.rowDelta
    let following = entries[end...].map { Entry(row: $0.row + delta, lines: $0.lines) }
    entries.replaceSubrange(start..., with: rewritten + following)
  }
}
