import AppKit

extension PaneTextView {
  /// The selection is copied, dragged and passed to services as plain text.
  override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

  /// Writes the selected text without its filler rows, which stand for no line of the file.
  override func writeSelection(
    to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]
  ) -> Bool {
    guard types.contains(.string) else { return false }
    pasteboard.clearContents()
    return pasteboard.setString(selectedTextWithoutFillerRows, forType: .string)
  }

  /// The selected text with every filler row left out, line feed and all; several selections
  /// are joined by line feeds.
  private var selectedTextWithoutFillerRows: String {
    let text = string as NSString
    return selectedRanges.map(\.rangeValue).filter { $0.length > 0 }.map { selection in
      let range = selection.location..<selection.location + selection.length
      let first = grid.row(containingOffset: range.lowerBound)
      let last = grid.row(containingOffset: range.upperBound - 1)
      return (first...last).filter { !content.isFiller(row: $0) }.map { row in
        text.substring(with: NSRange(grid.offsets(ofRow: row).clamped(to: range)))
      }.joined()
    }.joined(separator: "\n")
  }
}
