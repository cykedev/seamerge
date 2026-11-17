import AppKit
import Testing

/// The colors that TextKit draws the text of a text view in: those of the paragraphs it lays
/// out, where a color other than that of text is a color of its own.
@MainActor
enum DrawnColors {
  /// The color that the text at `offset` of `textView` is drawn in, or `nil` for the color of
  /// text; lays out the paragraph of the offset.
  static func color(at offset: Int, in textView: NSTextView) throws -> NSColor? {
    let manager = try #require(textView.textLayoutManager)
    let start = manager.documentRange.location
    let location = try #require(manager.location(start, offsetBy: offset))
    let fragment = try #require(manager.textLayoutFragment(for: location))
    let paragraph = try #require(fragment.textElement as? NSTextParagraph)
    let paragraphStart = manager.offset(
      from: start, to: try #require(paragraph.elementRange).location)
    let color =
      paragraph.attributedString.attribute(
        .foregroundColor, at: offset - paragraphStart, effectiveRange: nil) as? NSColor
    return color == NSColor.textColor ? nil : color
  }

  /// The ranges of the text of `textView` that are drawn in a color of their own, joined where
  /// they touch; lays out the whole text.
  static func coloredRanges(in textView: NSTextView) throws -> [Range<Int>] {
    let manager = try #require(textView.textLayoutManager)
    let start = manager.documentRange.location
    manager.ensureLayout(for: manager.documentRange)
    var ranges: [Range<Int>] = []
    manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
      guard let paragraph = fragment.textElement as? NSTextParagraph,
        let range = paragraph.elementRange
      else { return true }
      let paragraphStart = manager.offset(from: start, to: range.location)
      let text = paragraph.attributedString
      text.enumerateAttribute(
        .foregroundColor, in: NSRange(location: 0, length: text.length)
      ) { value, part, _ in
        guard let color = value as? NSColor, color != NSColor.textColor else { return }
        let colored = paragraphStart + part.location..<paragraphStart + part.upperBound
        if let last = ranges.last, last.upperBound == colored.lowerBound {
          ranges[ranges.count - 1] = last.lowerBound..<colored.upperBound
        } else {
          ranges.append(colored)
        }
      }
      return true
    }
    return ranges
  }
}
