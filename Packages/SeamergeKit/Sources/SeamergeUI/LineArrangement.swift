import Foundation

/// How a window lays out the lines of the files it compares: side by side on one row grid, side
/// by side as they are with bands between their changes, or a comparison in a single column.
///
/// The toolbar and the View menu choose among them, in the same words.
enum LineArrangement: CaseIterable {
  /// The panes side by side line up their lines, with filler rows where a side has fewer.
  case aligned

  /// The panes side by side show the lines of their files as they are, and bands in the seams
  /// connect their changes.
  case connected

  /// Both files of a comparison in one column: the lines they share once, and in each changed
  /// block the lines of one file above those of the other.
  case singleColumn

  /// The arrangement of a window that lines up its lines as `alignsLines` says, in a single
  /// column if `showsSingleColumn`.
  init(alignsLines: Bool, showsSingleColumn: Bool) {
    self = showsSingleColumn ? .singleColumn : alignsLines ? .aligned : .connected
  }

  /// The arrangements a window of a merge or a comparison offers: a merge none in one column.
  static func choices(inMerge isMerge: Bool) -> [LineArrangement] {
    isMerge ? [.aligned, .connected] : allCases
  }

  /// The name of the arrangement, which the View menu, the toolbar and Settings show.
  var title: String {
    switch self {
    case .aligned:
      String(
        localized: "Aligned Lines", bundle: .module,
        comment: "View menu, toolbar and Settings: matching lines of the files side by side.")
    case .connected:
      String(
        localized: "Connected Sides", bundle: .module,
        comment:
          "View menu, toolbar and Settings: the files side by side with bands between changes."
      )
    case .singleColumn:
      String(
        localized: "Single Column", bundle: .module,
        comment: "View menu, toolbar and Settings: both files of a comparison in one column.")
    }
  }

  /// The help tag of the arrangement in the View menu and the toolbar: what choosing it does.
  var help: String {
    switch self {
    case .aligned:
      String(
        localized: "Line up matching lines side by side", bundle: .module,
        comment: "Help tag of Aligned Lines in the View menu and the toolbar.")
    case .connected:
      String(
        localized: "Show each file without gaps and connect changes with bands", bundle: .module,
        comment: "Help tag of Connected Sides in the View menu and the toolbar.")
    case .singleColumn:
      String(
        localized: "Show removed lines above added lines in one column", bundle: .module,
        comment: "Help tag of Single Column in the View menu and the toolbar.")
    }
  }

  /// The command of the View menu that chooses the arrangement.
  var command: SessionCommand {
    switch self {
    case .aligned: .showAlignedLines
    case .connected: .showConnectedSides
    case .singleColumn: .showSingleColumn
    }
  }

  /// The name of the symbol that the toolbar shows for the arrangement.
  var symbolName: String {
    switch self {
    case .aligned: "rectangle.split.2x1"
    case .connected: "point.topleft.down.to.point.bottomright.curvepath"
    case .singleColumn: "rectangle.split.1x2"
    }
  }
}
