import CoreGraphics
import Foundation

/// The marks of the overview bar as they are drawn and hit: each at least as high as the
/// smallest mark, neighbors of the same kind merged where they touch, open conflicts on top.
struct OverviewLayout {
  /// A block that a shape stands for, with the middle of its own place in the bar.
  struct Member {
    var block: Int
    var middle: CGFloat
  }

  /// One mark as it is drawn, standing for one block or for several merged ones.
  struct Shape {
    var rect: CGRect
    var style: BlockStyle
    var isOpenConflict: Bool
    var members: [Member]
  }

  /// The shapes in the order they are drawn, open conflicts last, so that no other mark covers
  /// them.
  let shapes: [Shape]

  /// The place of each mark on its own, before merging, in the order of the marks.
  let markRects: [CGRect]

  /// The vertical extents of the strokes of matches, from the top down, strokes that touch
  /// merged.
  let matchSpans: [Range<CGFloat>]

  /// Lays out `marks` and the strokes of matches on `matchRows` of a grid with `rowCount` rows
  /// of `rowHeight` in `area`: the rows from its top down, the placements across its width.
  ///
  /// The rows fill the height of the area, but none takes more height than in the text: the
  /// marks of a text that fits beside the bar stand beside their rows, and the rest of the bar
  /// stays empty. A stroke lies across the middle of its row.
  init(
    marks: [OverviewMark], matchRows: IndexSet = [], rowCount: Int, rowHeight: CGFloat,
    area: CGRect
  ) {
    let scale = min(area.height / CGFloat(max(rowCount, 1)), rowHeight)
    let partialWidth = area.width * 2 / 3
    var markRects: [CGRect] = []
    var shapes: [Shape] = []
    // The index in `shapes` of the last shape of each kind, which the next mark of that kind
    // may merge with; marks come in row order.
    var lastShape: [Kind: Int] = [:]
    markRects.reserveCapacity(marks.count)
    for mark in marks {
      var top = area.minY + CGFloat(mark.rows.lowerBound) * scale
      var bottom = area.minY + CGFloat(mark.rows.upperBound) * scale
      if bottom - top < Theme.overviewMarkMinimumHeight {
        let middle = (top + bottom) / 2
        top = min(
          max(middle - Theme.overviewMarkMinimumHeight / 2, area.minY),
          area.maxY - Theme.overviewMarkMinimumHeight)
        bottom = top + Theme.overviewMarkMinimumHeight
      }
      let (left, width) =
        switch mark.placement {
        case .leading: (area.minX, partialWidth)
        case .trailing: (area.maxX - partialWidth, partialWidth)
        case .fullWidth: (area.minX, area.width)
        }
      let rect = CGRect(x: left, y: top, width: width, height: bottom - top)
      markRects.append(rect)
      let member = Member(block: mark.block, middle: rect.midY)
      let kind = Kind(placement: mark.placement, style: mark.style)
      if let index = lastShape[kind], shapes[index].rect.maxY + Self.mergeDistance >= rect.minY {
        shapes[index].rect = shapes[index].rect.union(rect)
        shapes[index].members.append(member)
      } else {
        lastShape[kind] = shapes.count
        shapes.append(
          Shape(
            rect: rect, style: mark.style, isOpenConflict: mark.isOpenConflict, members: [member]))
      }
    }
    self.shapes = shapes.filter { !$0.isOpenConflict } + shapes.filter(\.isOpenConflict)
    self.markRects = markRects
    var matchSpans: [Range<CGFloat>] = []
    let height = Theme.overviewMatchHeight
    for row in matchRows {
      let middle = area.minY + (CGFloat(row) + 0.5) * scale
      let top = min(max(middle - height / 2, area.minY), area.maxY - height)
      if let last = matchSpans.last, last.upperBound + Self.mergeDistance >= top {
        matchSpans[matchSpans.count - 1] = last.lowerBound..<max(last.upperBound, top + height)
      } else {
        matchSpans.append(top..<top + height)
      }
    }
    self.matchSpans = matchSpans
  }

  /// The block whose mark lies at height `y`, preferring open conflicts, or `nil` if no mark is
  /// near enough.
  func block(at y: CGFloat) -> Int? {
    let hit = shapes.filter {
      $0.rect.minY - Theme.overviewMarkHitSlop <= y && y <= $0.rect.maxY + Theme.overviewMarkHitSlop
    }
    let candidates = hit.contains(where: \.isOpenConflict) ? hit.filter(\.isOpenConflict) : hit
    return candidates.flatMap(\.members).min { abs($0.middle - y) < abs($1.middle - y) }?.block
  }

  /// How close marks of the same kind come before they merge.
  private static let mergeDistance: CGFloat = 1

  /// What marks must share to merge: their place across the bar and their color.
  private struct Kind: Hashable {
    var placement: OverviewMark.Placement
    var style: BlockStyle
  }
}
