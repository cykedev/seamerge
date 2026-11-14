import AppKit

/// Keeps several panes at the same place while any one of them scrolls.
///
/// The pane that scrolls leads; the others follow at once, without moving it back. Panes on the
/// same grid, with the same collapsed runs, follow to the same origin. Between panes whose rows
/// differ, the row mappings set with `setRowMapping(between:and:forward:backward:)` decide: the
/// follower puts the row that the mapping gives at its reading line, a quarter down from its top,
/// where the leader has the row it maps from. Mappings take and give rows of the grid; each pane
/// converts them to the rows it shows, with its collapsed runs.
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

  /// Runs `body`, in which panes move without the others following, as a pane does to keep its
  /// rows in place when its collapsed runs change.
  func withoutFollowing(_ body: () -> Void) {
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
    isSynchronizing = true
    defer { isSynchronizing = false }
    let origin = leader.scrollOrigin
    for follower in panes.compactMap(\.pane) where follower !== leader {
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
