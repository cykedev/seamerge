import Foundation

/// The localized pattern of a label, with placeholders `%@` for texts and `%lld` for numbers,
/// filled by joining its pieces: formatting each of the thousands of labels of a large file with
/// `String(format:)` takes most of what the labels cost.
///
/// A pattern with numbered placeholders, by which a translation may put the values in another
/// order, is filled by formatting.
struct LabelPattern: Sendable {
  /// The pattern with a text placeholder in place of each number placeholder.
  private let format: String

  /// The text before, between and after the placeholders, or `nil` for a pattern that is
  /// formatted.
  private let pieces: [String]?

  /// Takes `pattern`, a localized pattern.
  init(_ pattern: String) {
    format = pattern.replacing(/%(\d+\$)?lld/) { "%\($0.output.1 ?? "")@" }
    var pieces: [String] = []
    var rest = format[...]
    while let placeholder = rest.firstRange(of: "%") {
      guard rest[placeholder.upperBound...].hasPrefix("@") else {
        self.pieces = nil
        return
      }
      pieces.append(String(rest[..<placeholder.lowerBound]))
      rest = rest[placeholder.upperBound...].dropFirst()
    }
    pieces.append(String(rest))
    self.pieces = pieces
  }

  /// The label with `values` in place of the placeholders, in their order; a number is given
  /// as its digits.
  ///
  /// - Precondition: There is a value for each placeholder.
  func filled(_ values: String...) -> String {
    guard let pieces else {
      return String(format: format, arguments: values)
    }
    precondition(values.count == pieces.count - 1, "\(values.count) values for \(format)")
    var label = pieces[0]
    for (value, piece) in zip(values, pieces.dropFirst()) {
      label += value
      label += piece
    }
    return label
  }
}
