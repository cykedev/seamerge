/// The line numbers of a pane that shows both files of a comparison in one column: for each row,
/// its line in the file on the left and in the file on the right.
///
/// A row that both files share has both numbers, a removed line only the left one, an added line
/// only the right one. The gutter shows them in two columns, each as wide as the largest number
/// of either file needs.
public struct SideLineNumbers: Sendable, Hashable {
  /// The zero-based number of the line of the left file that each row shows, or -1.
  public let left: [Int32]

  /// The zero-based number of the line of the right file that each row shows, or -1.
  public let right: [Int32]

  /// Creates the line numbers of both files.
  ///
  /// - Precondition: Both have one entry per row, and each row shows a line of at least one file.
  public init(left: [Int32], right: [Int32]) {
    precondition(left.count == right.count, "Line numbers of both sides for different rows")
    precondition(
      zip(left, right).allSatisfy { $0 >= 0 || $1 >= 0 }, "A row shows a line of neither side")
    self.left = left
    self.right = right
  }

  /// The number of rows.
  var rowCount: Int { left.count }
}

extension SideLineNumbers {
  /// What VoiceOver calls the side of `row`: removed for a line of the left file alone, added for
  /// one of the right file alone, unchanged for a line both share.
  func sideName(ofRow row: Int) -> String {
    switch (left[row] >= 0, right[row] >= 0) {
    case (true, false): Marker.removed.accessibilityName
    case (false, true): Marker.added.accessibilityName
    default:
      String(
        localized: "Unchanged", bundle: .module,
        comment: "VoiceOver: a row of a single column that shows a line both files share.")
    }
  }

  /// Where `row` is, in words: the number of its line, or of its lines in both files where they
  /// differ.
  func placeDescription(ofRow row: Int) -> String {
    let (left, right) = (Int(left[row]) + 1, Int(right[row]) + 1)
    guard left > 0, right > 0, left != right else {
      return String(
        localized: "Line \(max(left, right))", bundle: .module,
        comment: "VoiceOver: where a mark is.")
    }
    return String(
      localized: "Line \(left) on the left, line \(right) on the right", bundle: .module,
      comment: "VoiceOver: where a row of a single column is that both files share.")
  }
}
