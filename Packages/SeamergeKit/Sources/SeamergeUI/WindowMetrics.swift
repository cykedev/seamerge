import Foundation

/// The sizes and distances of the window around the panes, on the 4-point grid.
enum WindowMetrics {
  /// The part of the window's height that the panes above the result take at first.
  static let sourcesFraction: CGFloat = 0.55

  /// The size of a new window.
  static let defaultContentSize = CGSize(width: 1280, height: 800)

  /// The least height of the panes above the result and of the result, so that the divider
  /// between them stays visible and a few rows show.
  static let minimumPaneHeight: CGFloat = 120
}
