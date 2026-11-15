import AppKit

extension PaneView {
  /// The number of UTF-16 code units of a line that a pane shows at most; a longer line ends
  /// after them with an ellipsis.
  ///
  /// The text of the pane keeps the whole line: copying, saving and editing see all of it.
  public nonisolated static let maximumShownLineLength = 20_000
}

/// How a pane shows a line too long to show whole: cut after
/// ``PaneView/maximumShownLineLength`` code units, at the end of a composed character, with an
/// ellipsis in place of the rest.
///
/// Laying out and drawing a line takes time in proportion to its length, so a line of some
/// hundred thousand characters, such as of minified code, would hold up every pass. What the pane
/// leaves out lies beyond its right edge, or hundreds of rows down, anyway.
enum LongLine {
  /// What stands in for the part of a line that the pane leaves out.
  static let mark = "\u{2026}"

  /// The number of code units of the line in `range` of `string`, its line feed left out, that
  /// the pane shows as they are.
  static func shownLength(of string: NSString, in range: Range<Int>) -> Int {
    let hasLineFeed = !range.isEmpty && string.character(at: range.upperBound - 1) == 0x0A
    let length = range.count - (hasLineFeed ? 1 : 0)
    guard length > PaneView.maximumShownLineLength else { return length }
    return string.rangeOfComposedCharacterSequence(
      at: range.lowerBound + PaneView.maximumShownLineLength
    ).location - range.lowerBound
  }

  /// Whether the line in `range` of `string` is cut.
  static func isCut(_ string: NSString, in range: Range<Int>) -> Bool {
    range.count > PaneView.maximumShownLineLength
      && shownLength(of: string, in: range)
        < range.count - (string.character(at: range.upperBound - 1) == 0x0A ? 1 : 0)
  }

  /// The text of the line in `range` of `string` without its line feed.
  static func wholeText(of string: NSString, in range: Range<Int>) -> String {
    let hasLineFeed = !range.isEmpty && string.character(at: range.upperBound - 1) == 0x0A
    return string.substring(
      with: NSRange(location: range.lowerBound, length: range.count - (hasLineFeed ? 1 : 0)))
  }

  /// The text of the line in `range` of `string` as the pane shows it, without its line feed.
  static func shownText(of string: NSString, in range: Range<Int>) -> String {
    let shown = string.substring(
      with: NSRange(location: range.lowerBound, length: shownLength(of: string, in: range)))
    return isCut(string, in: range) ? shown + mark : shown
  }
}

extension PaneTextView {
  /// Cuts `paragraph`, a paragraph of the pane's text, if it is too long to show whole, and puts
  /// the ellipsis in the color of previews in place of the rest; its line feed stays.
  func cutLongLine(_ paragraph: NSMutableAttributedString) {
    let string = paragraph.string as NSString
    let whole = 0..<string.length
    guard LongLine.isCut(string, in: whole) else { return }
    let cut = LongLine.shownLength(of: string, in: whole)
    let lineEnd =
      string.character(at: string.length - 1) == 0x0A ? string.length - 1 : string.length
    var attributes = paragraph.attributes(at: cut - 1, effectiveRange: nil)
    attributes[.foregroundColor] = theme.previewTextColor
    paragraph.replaceCharacters(
      in: NSRange(location: cut, length: lineEnd - cut),
      with: NSAttributedString(string: LongLine.mark, attributes: attributes))
  }

  /// The part of the paragraph at `offsets` in the pane's text that the pane shows as it is:
  /// all of it, or the part before the cut of a line that is too long.
  func shownOffsets(ofParagraph offsets: Range<Int>) -> Range<Int> {
    guard offsets.count > PaneView.maximumShownLineLength, let textStorage,
      !wholeRows.rows.contains(grid.row(containingOffset: offsets.lowerBound))
    else { return offsets }
    let string = textStorage.string as NSString
    guard LongLine.isCut(string, in: offsets) else { return offsets }
    return offsets.lowerBound..<offsets.lowerBound + LongLine.shownLength(of: string, in: offsets)
  }

  /// Shows whole the lines too long to show whole that the insertion point or the selection
  /// reaches into in an editable pane, and cuts again those it has left.
  ///
  /// Behind the cut, TextKit knows no places, so the insertion point would stand there unseen
  /// and typing or deleting would change text that nobody sees. A line the user works in costs
  /// the time it takes to lay out whole, as every line did before lines were cut.
  func showWholeTheLongLinesOfTheSelection() {
    let rows = longRowsOfTheSelection()
    guard rows != wholeRows.rows, let textStorage else { return }
    let changed = rows.symmetricDifference(wholeRows.rows)
    let text = textStorage.string as NSString
    wholeRows = (rows, rows.map { grid.wholeColumns(of: text, inRow: $0) }.max() ?? 0)
    // The content storage makes the paragraphs of the rows anew, cut or whole.
    textStorage.beginEditing()
    for row in changed {
      textStorage.edited(
        .editedAttributes, range: NSRange(grid.offsets(ofRow: row)), changeInLength: 0)
    }
    textStorage.endEditing()
    if lineWrapping != nil {
      for row in changed {
        rewrap(row: row, of: text)
      }
    }
    interaction?.textDidChange()
  }

  /// The rows of lines too long to show whole that the selection reaches into, none in a pane
  /// that cannot be edited.
  private func longRowsOfTheSelection() -> IndexSet {
    guard isEditable, let textStorage else { return [] }
    let text = textStorage.string as NSString
    var rows = IndexSet()
    for range in selectedRanges.map(\.rangeValue) {
      let first = grid.row(containingOffset: range.location)
      let last = grid.row(containingOffset: min(range.location + range.length, grid.textLength))
      for row in first...last where LongLine.isCut(text, in: grid.offsets(ofRow: row)) {
        rows.insert(row)
      }
    }
    return rows
  }
}
