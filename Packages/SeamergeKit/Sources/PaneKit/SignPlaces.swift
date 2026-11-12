import CoreGraphics

/// Where the signs of the decision column stand: each at the place of its block, unless that
/// would bring it closer to a neighbor than the room of a click.
///
/// A block without rows lies on the boundary between two rows, half a row from the first row of
/// the block after it and from the last row of a block of one row before it, so that their signs
/// would overlap. The signs move apart until each has the room of a click to itself, in the order
/// of their blocks. The sign of a block without rows gives way: it has no row of its own to stay
/// beside, while the sign of a block with rows stays beside its first row wherever it can. No
/// sign leaves the rows of the text: at its start and its end, the signs give way inwards.
struct SignPlaces {
  /// The place of a block's sign as its block asks for it.
  struct Anchor {
    /// The index of the block in the pane's content.
    var block: Int
    /// The vertical middle that the block asks for: its first row, or the boundary it lies on.
    var center: CGFloat
    /// Whether the block lies on a boundary between rows rather than on rows of its own.
    var liesBetweenRows: Bool
  }

  /// The vertical middle of each block's sign, by the index of its block.
  let centers: [Int: CGFloat]

  /// Places the signs of `anchors`, sorted by block, so that the middles of any two are at least
  /// `spacing` apart and stay as close to their anchors as that allows, each with the room of a
  /// click within `area`, the rows of the text.
  ///
  /// The signs that would come too close form a group spaced evenly by `spacing`, placed where
  /// the squared distances from the anchors, weighted, are least. A sign on a boundary weighs
  /// almost nothing, so that it moves while a sign beside its row stays. Signs that would then
  /// stand beyond the ends of `area` move inwards, pushing their neighbors on; only where the
  /// text is too short for all of them do they reach below its end.
  ///
  /// The places depend on the anchors relative to `area` alone, so that scrolling moves every
  /// sign by the same distance.
  init(anchors: [Anchor], spacing: CGFloat, within area: ClosedRange<CGFloat>) {
    let origin = area.lowerBound
    var groups: [Group] = []
    for var anchor in anchors {
      anchor.center -= origin
      var group = Group(anchor)
      while let previous = groups.last, previous.end(spacing: spacing) + spacing > group.start {
        groups.removeLast()
        group = previous.joined(with: group, spacing: spacing)
      }
      groups.append(group)
    }
    var places = groups.flatMap { group in
      group.anchors.indices.map { (group.anchors[$0].block, group.start + CGFloat($0) * spacing) }
    }
    let lowest = spacing / 2
    let highest = max(
      area.upperBound - origin - spacing / 2, lowest + CGFloat(max(places.count - 1, 0)) * spacing)
    for index in places.indices {
      let floor = index == 0 ? lowest : places[index - 1].1 + spacing
      places[index].1 = max(places[index].1, floor)
    }
    for index in places.indices.reversed() {
      let ceiling = index == places.count - 1 ? highest : places[index + 1].1 - spacing
      places[index].1 = min(places[index].1, ceiling)
    }
    centers = Dictionary(uniqueKeysWithValues: places.map { ($0.0, $0.1.rounded() + origin) })
  }

  /// The block whose sign covers `y`, within half of `spacing` of its middle, if any; the one
  /// nearest to `y` if two do.
  func block(atY y: CGFloat, spacing: CGFloat) -> Int? {
    centers.filter { abs($0.value - y) <= spacing / 2 }
      .min { abs($0.value - y) < abs($1.value - y) }?.key
  }

  /// Signs that stand one `spacing` apart, from `start` on.
  private struct Group {
    var anchors: [Anchor]
    var start: CGFloat

    init(_ anchor: Anchor) {
      anchors = [anchor]
      start = anchor.center
    }

    private init(anchors: [Anchor], spacing: CGFloat) {
      self.anchors = anchors
      // The start that minimizes the weighted squared distances of the signs from their anchors.
      var weightedSum: CGFloat = 0
      var totalWeight: CGFloat = 0
      for (index, anchor) in anchors.enumerated() {
        let weight = Self.weight(of: anchor)
        weightedSum += weight * (anchor.center - CGFloat(index) * spacing)
        totalWeight += weight
      }
      start = weightedSum / totalWeight
    }

    func end(spacing: CGFloat) -> CGFloat {
      start + CGFloat(anchors.count - 1) * spacing
    }

    func joined(with other: Group, spacing: CGFloat) -> Group {
      Group(anchors: anchors + other.anchors, spacing: spacing)
    }

    /// How strongly a sign holds on to its anchor.
    private static func weight(of anchor: Anchor) -> CGFloat {
      anchor.liesBetweenRows ? 1 / 1024 : 1
    }
  }
}
