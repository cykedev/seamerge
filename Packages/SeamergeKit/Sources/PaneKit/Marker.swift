/// The mark in the gutter at the first row of a block that tells how a side changed it.
public enum Marker: Sendable, Hashable {
  /// The side added lines; shown as `+`.
  case added
  /// The side changed lines; shown as `~`.
  case changed
  /// The side removed lines; shown as `−`.
  case removed
}

/// The mark `!` in the gutter at the first row of a conflict.
public enum ConflictMarker: Sendable, Hashable, CaseIterable {
  /// The conflict still needs a decision; drawn in the conflict color.
  case open
  /// The conflict has been decided; drawn in the secondary label color.
  case resolved
}
