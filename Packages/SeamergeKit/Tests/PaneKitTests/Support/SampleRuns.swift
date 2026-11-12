import PaneKit

extension SampleMerge {
  /// The sample merge with longer stretches of unchanged lines: some of its changes are taken
  /// back, so that their lines read the same on every side.
  static let transcoderWithLongUnchangedRuns: SampleMerge = {
    let chunks = transcoder.chunks
    func same(_ range: ClosedRange<Int>) -> Chunk {
      .same(
        range.flatMap { index -> [String] in
          switch chunks[index] {
          case .same(let lines): lines
          case .onlyA(_, let base, _), .onlyB(let base, _, _), .both(_, let base, _, _),
            .conflict(_, let base, _, _, _):
            base
          }
        })
    }
    return SampleMerge(
      chunks: [same(0...4), chunks[5], same(6...8), chunks[9], chunks[10], chunks[11], chunks[12]],
      ignoredDifferenceRowsOfB: [])
  }()
}

extension PaneContent {
  /// The runs that collapse in this content by the rule of the merge model: rows outside every
  /// block, at least 8 in a row, less 3 rows of context on each side that is not an edge.
  var collapsibleRuns: [CollapsedRun] {
    let rowCount = lineNumbers.count
    let gaps = zip(
      [0] + blocks.map(\.rows.upperBound), blocks.map(\.rows.lowerBound) + [rowCount])
    return gaps.compactMap { start, end in
      guard end - start >= 8 else { return nil }
      let first = start == 0 ? 0 : start + 3
      let last = end == rowCount ? rowCount : end - 3
      return CollapsedRun(rows: first..<last)
    }
  }
}

extension SampleMerge {
  /// The runs that collapse in the upper panes and in the result, by the rule of the merge model:
  /// each stretch of unchanged lines of at least 8 rows, less 3 rows of context on each side
  /// that is not an edge of the files, hiding the same lines above and below.
  func collapsedRuns() -> (upper: [CollapsedRun], result: [CollapsedRun]) {
    let anchors = rowAnchors()
    let end = anchors[anchors.count - 1]
    var upper: [CollapsedRun] = []
    var result: [CollapsedRun] = []
    for (index, chunk) in chunks.enumerated() {
      guard case .same(let lines) = chunk, lines.count >= 8 else { continue }
      let start = anchors[index]
      let before = start.upper == 0 ? 0 : 3
      let after = start.upper + lines.count == end.upper ? 0 : 3
      upper.append(CollapsedRun(rows: start.upper + before..<start.upper + lines.count - after))
      result.append(CollapsedRun(rows: start.result + before..<start.result + lines.count - after))
    }
    return (upper, result)
  }
}
