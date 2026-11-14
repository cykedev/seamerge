import CoreGraphics

/// The common track over which panes side by side scroll that show the lines of their files
/// rather than line up their rows: each stretch, a changed block or the unchanged rows between
/// two, is as long on the track as in the pane that shows it highest.
///
/// Each pane takes a place on the track to a place of its own, in proportion within each
/// stretch: across a stretch that it shows lower than another pane, it moves more slowly, and
/// across one in which it has no rows, it stands still on the hairline that marks them. So no
/// pane jumps, whichever of them scrolls. Places are the heights of the reading line, in points
/// from the top of the text; the stretches are measured as the panes show their rows, with
/// collapsed runs and wrapped lines.
struct ScrollTrack {
  /// For each pane, where each stretch starts in its text, followed by where the last one ends.
  private let boundaries: [[CGFloat]]

  /// Where each stretch starts on the track, followed by where the last one ends.
  private let starts: [CGFloat]

  /// Measures the track of `panes`, which show the same changed blocks in the same order, or
  /// gives `nil` while they show different numbers of blocks, as for a moment while they get
  /// new content one after the other.
  @MainActor
  init?(panes: [PaneView]) {
    let blockCount = panes.first?.content.blocks.count ?? 0
    guard panes.allSatisfy({ $0.content.blocks.count == blockCount }) else { return nil }
    boundaries = panes.map { pane in
      let blocks = pane.content.blocks
      let rowCount = pane.content.lineNumbers.count
      var rows = [0]
      for block in blocks {
        rows += [block.rows.lowerBound, block.rows.upperBound]
      }
      rows.append(rowCount)
      return rows.map { pane.verticalSpan(ofRows: $0..<$0).lowerBound }
    }
    let stretchCount = 2 * blockCount + 1
    var starts: [CGFloat] = [0]
    starts.reserveCapacity(stretchCount + 1)
    for stretch in 0..<stretchCount {
      let length = boundaries.map { $0[stretch + 1] - $0[stretch] }.max() ?? 0
      starts.append(starts[stretch] + length)
    }
    self.starts = starts
  }

  /// The place in the text of the pane at `index` at the place `position` of the track.
  ///
  /// Before the track and beyond it, places go on one for one.
  func place(ofPane index: Int, atTrackPosition position: CGFloat) -> CGFloat {
    let ends = boundaries[index]
    guard position > starts[0] else { return ends[0] + position - starts[0] }
    guard position < starts[starts.count - 1] else {
      return ends[ends.count - 1] + position - starts[starts.count - 1]
    }
    let stretch = starts.partitioningIndex { $0 > position } - 1
    let length = starts[stretch + 1] - starts[stretch]
    let own = ends[stretch + 1] - ends[stretch]
    return ends[stretch] + (position - starts[stretch]) / length * own
  }

  /// The places of the track at which the pane at `index` stands at `place` of its text: a
  /// single one, or a range where the pane stands still across stretches in which it has no
  /// rows.
  func trackPositions(ofPane index: Int, atPlace place: CGFloat) -> ClosedRange<CGFloat> {
    let ends = boundaries[index]
    let stretchCount = ends.count - 1
    guard place >= ends[0], place <= ends[stretchCount] else {
      let edge = place < ends[0] ? 0 : stretchCount
      let position = starts[edge] + place - ends[edge]
      return position...position
    }
    // The first stretch that reaches the place, and the last that starts at or before it.
    let first = max(ends.partitioningIndex { $0 >= place } - 1, 0)
    let last = min(ends.partitioningIndex { $0 > place } - 1, stretchCount - 1)
    let lower = position(in: first, ofPane: index, atPlace: place, isLast: false)
    let upper = position(in: last, ofPane: index, atPlace: place, isLast: true)
    return lower...max(upper, lower)
  }

  /// The place of the track in `stretch` at which the pane at `index` stands at `place`; for a
  /// stretch in which the pane has no rows, its start, or its end if `isLast`.
  private func position(
    in stretch: Int, ofPane index: Int, atPlace place: CGFloat, isLast: Bool
  ) -> CGFloat {
    let ends = boundaries[index]
    let own = ends[stretch + 1] - ends[stretch]
    let length = starts[stretch + 1] - starts[stretch]
    guard own > 0 else { return isLast ? starts[stretch + 1] : starts[stretch] }
    return starts[stretch] + (place - ends[stretch]) / own * length
  }
}
