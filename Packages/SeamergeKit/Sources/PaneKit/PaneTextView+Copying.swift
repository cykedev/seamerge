import AppKit

extension PaneTextView {
  /// The selection is copied, dragged and passed to services as plain text.
  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

  /// Writes the selected text without its filler rows and previews, which stand for no line of
  /// the file.
  override func writeSelection(
    to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]
  ) -> Bool {
    guard types.contains(.string) else { return false }
    pasteboard.clearContents()
    return pasteboard.setString(copiedText, forType: .string)
  }

  /// The selected text with every filler row left out, line feed and all, and the previews left
  /// out; several selections are joined by line feeds.
  private var copiedText: String {
    let text = string as NSString
    return selectedRanges.map(\.rangeValue).filter { $0.length > 0 }.map { selection in
      let range = selection.location..<selection.location + selection.length
      let first = grid.row(containingOffset: range.lowerBound)
      let last = grid.row(containingOffset: range.upperBound - 1)
      return (first...last).filter { !content.isFiller(row: $0) }.flatMap { row in
        textOutsidePreviews(in: grid.offsets(ofRow: row).clamped(to: range))
      }.map { text.substring(with: NSRange($0)) }.joined()
    }.joined(separator: "\n")
  }

  /// The parts of `range` outside the previews.
  private func textOutsidePreviews(in range: Range<Int>) -> [Range<Int>] {
    var parts: [Range<Int>] = []
    var start = range.lowerBound
    for span in previewSpans where span.overlaps(range) {
      if start < span.lowerBound {
        parts.append(start..<span.lowerBound)
      }
      start = max(start, span.upperBound)
    }
    if start < range.upperBound {
      parts.append(start..<range.upperBound)
    }
    return parts
  }
}
