/// The runs of a code span marker on one line, each paired with the next run of the same
/// length, so that finding the end of a code span never scans the rest of the line again.
struct CodeSpanRuns {
  private var runs: [Range<Int>] = []
  /// For each run, the index of the next run of the same length.
  private var closingRuns: [Int?] = []
  /// The first run that may still open a code span.
  private var cursor = 0

  init(marker: UInt8, in line: LineBytes) {
    var position = 0
    while let start = line.firstPosition(of: marker, from: position) {
      var end = start + 1
      while line.byte(at: end) == marker { end += 1 }
      runs.append(start..<end)
      position = end
    }
    closingRuns = [Int?](repeating: nil, count: runs.count)
    var nextRunByLength: [Int: Int] = [:]
    for index in runs.indices.reversed() {
      closingRuns[index] = nextRunByLength[runs[index].count]
      nextRunByLength[runs[index].count] = index
    }
  }

  /// The end of the run at a position, or of the code span it opens when a run of the same
  /// length follows.
  ///
  /// - Precondition: A run starts at `position`, and positions are asked for in increasing
  ///   order.
  mutating func end(ofSpanStartingAt position: Int) -> (end: Int, isCodeSpan: Bool) {
    while cursor < runs.count, runs[cursor].lowerBound < position { cursor += 1 }
    precondition(
      cursor < runs.count && runs[cursor].lowerBound == position, "No run starts at \(position)")
    let opening = cursor
    guard let closing = closingRuns[opening] else {
      cursor += 1
      return (runs[opening].upperBound, false)
    }
    cursor = closing + 1
    return (runs[closing].upperBound, true)
  }
}
