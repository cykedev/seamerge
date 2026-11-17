import Foundation

/// The sizes and distances of the sheets of files, on the 4-point grid.
enum CompareFilesMetrics {
  /// The margin between the content and the edges of the sheet.
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

  /// The width of the border of a field that a drop would fill.
  static let dropTargetBorderWidth: CGFloat = 3

  /// The distance between a field and the word for its role below it.
  static let captionSpacing: CGFloat = 8

  /// The distance between the fields and the buttons that open them.
  static let sectionSpacing: CGFloat = 20
}
