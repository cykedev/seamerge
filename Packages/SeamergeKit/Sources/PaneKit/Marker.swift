import Foundation

/// The mark in the gutter at the first row of a block that tells how a side changed it.
package enum Marker: Sendable, Hashable {
  /// The side added lines; shown as `+`.
  case added
  /// The side changed lines; shown as `~`.
  case changed
  /// The side removed lines; shown as `−`.
  case removed
}

/// The mark `!` in the gutter at the first row of a conflict.
package enum ConflictMarker: Sendable, Hashable, CaseIterable {
  /// The conflict still needs a decision; drawn in the conflict color.
  case open
  /// The conflict has been decided; drawn in the secondary label color.
  case resolved
}

extension Marker {
  /// What VoiceOver calls the mark, and a row of a single column that shows a line of one file
  /// alone: removed for the left file, added for the right one.
  var accessibilityName: String {
    switch self {
    case .added:
      String(localized: "Added", bundle: .module, comment: "VoiceOver: the side added lines.")
    case .changed:
      String(localized: "Changed", bundle: .module, comment: "VoiceOver: the side changed lines.")
    case .removed:
      String(localized: "Removed", bundle: .module, comment: "VoiceOver: the side removed lines.")
    }
  }
}
