import Foundation

/// What the marks beside the rows mean, as their help tags and the help that VoiceOver reads:
/// one sentence for each, which begins with a verb and does not repeat the mark's name.
enum MarkHelp {
  /// What the mark of how a side changed a block means.
  static func marker(_ marker: Marker) -> String {
    switch marker {
    case .added:
      String(
        localized: "Appears only on this side", bundle: .module,
        comment: "Help tag of the + in the gutter.")
    case .changed:
      String(
        localized: "Differs on this side", bundle: .module,
        comment: "Help tag of the ~ in the gutter.")
    case .removed:
      String(
        localized: "Lacks lines here that the other side has", bundle: .module,
        comment: "Help tag of the − in the gutter.")
    }
  }

  /// What the mark of a conflict means.
  static func conflict(_ conflict: ConflictMarker) -> String {
    switch conflict {
    case .open:
      String(
        localized: "Differs on both sides; choose what the result takes",
        bundle: .module, comment: "Help tag of the sign of an open conflict.")
    case .resolved:
      String(
        localized: "Differed on both sides; the result takes what you chose",
        bundle: .module, comment: "Help tag of the sign of a resolved conflict.")
    }
  }

  /// What the ring of a line whose difference the comparison ignores means.
  static var ignoredDifference: String {
    String(
      localized: "Differs only in whitespace or line endings, which this comparison ignores",
      bundle: .module, comment: "Help tag of the ring in the gutter.")
  }

  /// What the sign that collapses an expanded run of unchanged lines does.
  static var collapseRun: String {
    String(
      localized: "Collapses these unchanged lines again", bundle: .module,
      comment: "Help tag of the sign beside an expanded run of unchanged lines.")
  }
}
