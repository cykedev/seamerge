import Foundation

/// The sizes and distances of the window Compare Files, on the 4-point grid.
enum CompareFilesMetrics {
  /// The margin between the content and the edges of the window.
  static let margin: CGFloat = 20

  /// The size of a field.
  static let fieldSize = CGSize(width: 184, height: 112)

  /// The distance between two fields.
  static let fieldSpacing: CGFloat = 12

  /// The radius of the corners of a field.
  static let fieldCornerRadius: CGFloat = 10

  /// The distance of a field's content from its edges.
  static let fieldInset: CGFloat = 12

  /// The distance between the parts of a field's content.
  static let fieldContentSpacing: CGFloat = 4

  /// The size of the icon of a file in a field.
  static let iconSize: CGFloat = 32

  /// The length of the dashes and gaps of the border of an optional field.
  static let dashLength: CGFloat = 4

  /// The width of the border of a field that a drop would fill.
  static let dropTargetBorderWidth: CGFloat = 3

  /// The distance between a field and the word for its role below it.
  static let captionSpacing: CGFloat = 8

  /// The distance between the fields and the button that opens them, and between that button
  /// and the recent comparisons.
  static let sectionSpacing: CGFloat = 20

  /// The distance between the heading of the recent comparisons and their list.
  static let headingSpacing: CGFloat = 4

  /// The height of a line of the recent comparisons.
  static let recentRowHeight: CGFloat = 24

  /// How many recent comparisons the window lists.
  static let recentRowCount = 5

  /// The room at the bottom of the window that the line about Git takes.
  static let gitStatusHeight: CGFloat = 44
}
