import AppKit

/// Keeps several panes at the same place while any one of them scrolls.
///
/// The pane that scrolls leads; the others follow at once, without moving it back. Panes on the
/// same grid, with the same collapsed runs, follow to the same origin. Between panes whose rows
/// differ, the row mappings set with `setRowMapping(between:and:forward:backward:)` decide: the
/// follower puts the row that the mapping gives at its reading line, a quarter down from its top,
/// where the leader has the row it maps from. Mappings take and give rows of the grid; each pane
/// converts them to the rows it shows, with its collapsed runs. Panes side by side that show the
/// lines of their files scroll over a common track (`setTrack(for:)`), on which each pane moves
/// steadily, standing still across a block in which it has no rows.
///
/// Sideways, all panes share one position, also while they bounce at an edge, and one scroll
/// range: that of the pane that needs the widest, so that the text of every pane reaches as far.
@MainActor
public final class ScrollSync {
  /// Whether the panes follow each other; while off, each pane scrolls on its own.
  ///
  /// Turned on again, the panes follow the pane that scrolled last.
  public var isEnabled = true {
    didSet {
      if isEnabled && !oldValue, let lastLeader {
        follow(lastLeader)
      }
    }
  }

  /// The pane that scrolled last on its own, also while the coupling is off.
  private weak var lastLeader: PaneView?

  private var panes: [WeakPane] = []
  private var mappings: [Pair: @MainActor (Double) -> Double] = [:]
  private var isSynchronizing = false

  /// The panes that scroll over the common track, from left to right.
  private var trackPanes: [WeakPane] = []

  /// The track of ``trackPanes`` as they show their rows now, measured when first needed.
  private var measuredTrack: ScrollTrack?

  /// The place of the track at the reading line, where the coupling last left the panes on it,
  /// or `nil` until it has.
  private var trackPosition: CGFloat?

  /// The height of the reading line of each pane on the track, where the coupling last left
  /// it.
  private var trackPlaces: [ObjectIdentifier: CGFloat] = [:]

  /// Creates a coupling without panes.
  public init() {}

  isolated deinit {
    for pane in panes.compactMap(\.pane) {
      stopObserving(pane)
    }
  }

  /// Couples `pane` to the panes that are already coupled.
  ///
  /// - Precondition: `pane` belongs to no coupling.
  public func add(_ pane: PaneView) {
    precondition(pane.scrollSync == nil, "A pane belongs to one scroll coupling at most")
    panes.removeAll { $0.pane == nil }
    panes.append(WeakPane(pane: pane))
    pane.scrollSync = self
    NotificationCenter.default.addObserver(
      self, selector: #selector(clipViewBoundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification, object: pane.clipView)
    updateHorizontalScrollRange()
  }

  /// Releases `pane`, which then scrolls on its own, and forgets its mappings.
  public func remove(_ pane: PaneView) {
    guard pane.scrollSync === self else { return }
    stopObserving(pane)
    panes.removeAll { $0.pane == nil || $0.pane === pane }
    if trackPanes.contains(where: { $0.pane === pane }) {
      setTrack(for: [])
    }
    let identifier = ObjectIdentifier(pane)
    mappings = mappings.filter { $0.key.leader != identifier && $0.key.follower != identifier }
    updateHorizontalScrollRange()
  }

  /// Sets how two panes whose rows differ follow each other vertically, in both directions.
  ///
  /// `forward` takes the row at the reading line of `first`, with its fraction, to the row that
  /// `second` puts at its own reading line; `backward` does the same from `second` to `first`.
  /// Panes without mappings between them take each other's origin, which is right only for panes
  /// on the same grid.
  ///
  /// - Precondition: `first` and `second` are different panes.
  public func setRowMapping(
    between first: PaneView, and second: PaneView,
    forward: @escaping @MainActor (Double) -> Double,
    backward: @escaping @MainActor (Double) -> Double
  ) {
    precondition(first !== second, "A pane needs no row mapping to itself")
    let (firstID, secondID) = (ObjectIdentifier(first), ObjectIdentifier(second))
    mappings[Pair(leader: firstID, follower: secondID)] = forward
    mappings[Pair(leader: secondID, follower: firstID)] = backward
  }

  /// Ends the mappings between `first` and `second` in both directions, after which they take
  /// each other's origin, as panes on the same grid do.
  public func removeRowMapping(between first: PaneView, and second: PaneView) {
    let (firstID, secondID) = (ObjectIdentifier(first), ObjectIdentifier(second))
    mappings[Pair(leader: firstID, follower: secondID)] = nil
    mappings[Pair(leader: secondID, follower: firstID)] = nil
  }

  /// Lets `panes`, side by side and showing the lines of their files, scroll over a common
  /// track, on which each stretch, a changed block or the unchanged rows between two, is as long
  /// as in the pane that shows it highest; an empty array ends the track.
  ///
  /// Each pane follows the track steadily, in proportion within each stretch: more slowly
  /// across a block it shows lower, and not at all across one in which it has no rows, its
  /// hairline then at the reading line. A pane that the user scrolls by hand moves the track by
  /// as much as it moved and takes its own place on it, so that it too stands still across such
  /// a block; a pane that scrolls to a place, as to a block or the insertion point, puts the
  /// track where it stands there.
  ///
  /// - Precondition: The panes belong to this coupling and show the same changed blocks.
  public func setTrack(for panes: [PaneView]) {
    trackPanes = panes.map { WeakPane(pane: $0) }
    measuredTrack = nil
    trackPosition = nil
    trackPlaces = [:]
  }

  /// Moves the other panes to where `pane` stands, as if it had scrolled there: after the panes
  /// changed how they show their rows, so that they stand together again before the user
  /// scrolls; nothing happens while the panes do not follow each other.
  public func align(to pane: PaneView) {
    guard isEnabled, pane.scrollSync === self else { return }
    lastLeader = pane
    follow(pane)
  }

  /// Forgets what the track of `pane` measured, after the pane changed how it shows its rows.
  func trackDidChange(of pane: PaneView) {
    guard trackPanes.contains(where: { $0.pane === pane }) else { return }
    measuredTrack = nil
    trackPosition = nil
  }

  /// Runs `body`, in which panes move without the others following, as a pane does to keep its
  /// rows in place when its collapsed runs change, or as panes do while they get new content one
  /// after the other.
  public func withoutFollowing(_ body: () -> Void) {
    let wasSynchronizing = isSynchronizing
    isSynchronizing = true
    defer { isSynchronizing = wasSynchronizing }
    body()
  }

  /// Gives every pane the scroll range of the pane that needs the widest; called when a pane's
  /// own need changes.
  func updateHorizontalScrollRange() {
    let coupled = panes.compactMap(\.pane)
    let range = coupled.map(\.ownHorizontalScrollRange).max() ?? 0
    for pane in coupled {
      pane.sharedHorizontalScrollRange = range
    }
  }

  @objc private func clipViewBoundsDidChange(_ notification: Notification) {
    guard
      !isSynchronizing,
      let leader = panes.lazy.compactMap(\.pane).first(where: {
        $0.clipView === notification.object as AnyObject
      })
    else { return }
    lastLeader = leader
    if isEnabled {
      follow(leader)
    }
  }

  /// Moves every other pane to where `leader` stands.
  private func follow(_ leader: PaneView) {
    // Setting the followers' origins posts their notifications at once; they must not lead.
    let wasSynchronizing = isSynchronizing
    isSynchronizing = true
    defer { isSynchronizing = wasSynchronizing }
    let onTrack = followOnTrack(leader)
    let origin = leader.scrollOrigin
    for follower in panes.compactMap(\.pane)
    where follower !== leader && !onTrack.contains(follower) {
      let y =
        mappings[Pair(leader: ObjectIdentifier(leader), follower: ObjectIdentifier(follower))]
        .map { mapping in
          let line = (origin.y + Theme.readingLine * leader.visibleHeight) / leader.rowHeight
          let row = mapping(leader.displayRows.rowPosition(ofLine: Double(line)))
          return CGFloat(follower.displayRows.linePosition(ofRow: row)) * follower.rowHeight
            - Theme.readingLine * follower.visibleHeight
        } ?? origin.y
      // Sideways the follower takes the leader's position as it is, beyond an edge too, so that
      // the panes bounce together; vertically panes do not bounce.
      let target = CGPoint(x: origin.x, y: min(max(y, 0), follower.verticalScrollRange))
      if follower.scrollOrigin != target {
        follower.scroll(to: target)
      }
    }
  }

  /// Moves the panes on the track to where `leader` puts the track, `leader` too if the user
  /// scrolls it by hand, and returns them; none if `leader` is not on the track.
  ///
  /// While the panes show different blocks, the track cannot be measured; they stay where they
  /// are until they show the same blocks again.
  private func followOnTrack(_ leader: PaneView) -> [PaneView] {
    let onTrack = trackPanes.compactMap(\.pane)
    guard let leaderIndex = onTrack.firstIndex(where: { $0 === leader }) else { return [] }
    guard let track = measuredTrack ?? ScrollTrack(panes: onTrack) else {
      trackPosition = nil
      return onTrack
    }
    measuredTrack = track
    let place = leader.readingLinePlace
    let leaderID = ObjectIdentifier(leader)
    var position: CGFloat
    if leader.isScrolledByHand, let previous = trackPosition, let left = trackPlaces[leaderID] {
      position = previous + place - left
    } else {
      let positions = track.trackPositions(ofPane: leaderIndex, atPlace: place)
      position = min(
        max(trackPosition ?? positions.lowerBound, positions.lowerBound),
        positions.upperBound)
    }
    let x = leader.scrollOrigin.x
    for (index, pane) in onTrack.enumerated() where pane !== leader || leader.isScrolledByHand {
      pane.placeReadingLine(at: track.place(ofPane: index, atTrackPosition: position), x: x)
    }
    let places = onTrack.map(\.readingLinePlace)
    if let previous = trackPosition,
      zip(onTrack, places).allSatisfy({ trackPlaces[ObjectIdentifier($0)] == $1 })
    {
      // Where no pane can go any further, at the top or the end of their texts, the track stays,
      // so that the panes move again at once when the user turns back. A pane at the end of its
      // text while another goes on stays there until the track comes back to it.
      position = previous
    }
    trackPosition = position
    for (pane, place) in zip(onTrack, places) {
      trackPlaces[ObjectIdentifier(pane)] = place
    }
    return onTrack
  }

  private func stopObserving(_ pane: PaneView) {
    NotificationCenter.default.removeObserver(
      self, name: NSView.boundsDidChangeNotification, object: pane.clipView)
    pane.scrollSync = nil
    pane.sharedHorizontalScrollRange = nil
  }

  private struct WeakPane {
    weak var pane: PaneView?
  }

  private struct Pair: Hashable {
    var leader: ObjectIdentifier
    var follower: ObjectIdentifier
  }
}
