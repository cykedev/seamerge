import Foundation

/// The sizes and distances of the window around the panes, on the 4-point grid.
enum WindowMetrics {
  /// The height of a pane header.
  static let headerHeight: CGFloat = 28

  /// The height of the line below the result header that says Git no longer waits.
  static let noticeHeight: CGFloat = 24

  /// The distance of a header's content from the edges of its pane.
  static let headerInset: CGFloat = 12

  /// The distance between the parts of a header.
  static let headerSpacing: CGFloat = 8

  /// The least width and height of a control that is clicked.
  static let minimumHitTarget: CGFloat = 20

  /// The height of the badge of a side.
  static let badgeHeight: CGFloat = 16

  /// The room on either side of the letter in a badge.
  static let badgePadding: CGFloat = 4

  /// The margin around the details of a side.
  static let detailsInset: CGFloat = 16

  /// The distance between the title of the details and their facts.
  static let detailsSpacing: CGFloat = 12

  /// The distance between the facts of the details.
  static let detailsRowSpacing: CGFloat = 4

  /// The widest the details of a side get before their lines wrap.
  static let detailsMaximumWidth: CGFloat = 400

  /// The part of the window's height that the panes above the result take at first.
  static let sourcesFraction: CGFloat = 0.55

  /// The room the title bar keeps before the title for the window's buttons.
  static let titlebarControlsWidth: CGFloat = 80

  /// The least room between the subtitle and the items of the toolbar.
  static let toolbarSpacing: CGFloat = 16

  /// The width of the field of Go to Line.
  static let lineFieldWidth: CGFloat = 200

  /// The size of a new window.
  static let defaultContentSize = CGSize(width: 1280, height: 800)

  /// The least height of the panes above the result and of the result, so that the divider
  /// between them stays visible and a few rows show.
  static let minimumPaneHeight: CGFloat = 120
}
