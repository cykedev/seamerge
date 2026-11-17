import Foundation

/// The sizes and distances of the welcome window, on the 4-point grid.
enum WelcomeMetrics {
  /// The size of the content of the window, which the user cannot change.
  static let contentSize = CGSize(width: 760, height: 460)

  /// The width of the column with the name of the app.
  static let sidebarWidth: CGFloat = 250

  /// The room at the top of the column that the buttons of the title bar take.
  static let titleBarHeight: CGFloat = 40

  /// The distance of the content of the column from its sides and its bottom.
  static let sidebarInset: CGFloat = 20

  /// The size of the icon of the app.
  static let iconSize: CGFloat = 96

  /// The distance between the icon, the name and the version.
  static let nameSpacing: CGFloat = 4

  /// The distance between the version and the buttons.
  static let actionsSpacing: CGFloat = 28

  /// The distance between two buttons.
  static let actionSpacing: CGFloat = 8

  /// The height of the place to drop files.
  static let dropAreaHeight: CGFloat = 84

  /// The radius of the corners of the place to drop files.
  static let dropAreaCornerRadius: CGFloat = 12

  /// The width of the border of the place to drop files, quiet and while a drop would be taken.
  static let dropAreaBorderWidth: (quiet: CGFloat, target: CGFloat) = (1, 2)

  /// The margin between the list and the edges of the window.
  static let listMargin: CGFloat = 20

  /// The distance between the heading of the recent comparisons and their list.
  static let headingSpacing: CGFloat = 4

  /// The height of a line of the recent comparisons.
  static let recentRowHeight: CGFloat = 24

  /// How many recent comparisons the window lists.
  static let recentRowCount = 5

  /// The room at the bottom of the list that the line about Git takes.
  static let gitStatusHeight: CGFloat = 40
}
