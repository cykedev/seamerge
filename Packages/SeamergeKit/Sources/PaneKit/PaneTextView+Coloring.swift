import AppKit
import TextBasics

extension PaneTextView {
  /// Whether some text of the pane has a color of its own: previews, or code colored by its
  /// syntax.
  var colorsText: Bool { !previewSpans.isEmpty || syntaxProvider != nil }

  /// Gives the text of `paragraph`, the paragraph of the pane's text that starts at offset
  /// `start`, its colors as the content storage makes it: the previews the preview color, and
  /// the tokens of the syntax provider within the first `shownLength` code units theirs.
  ///
  /// The colors belong to the paragraph that TextKit lays out rather than to the text, so that
  /// they are neither copied nor passed on to text typed next to them, and TextKit holds them
  /// with the paragraphs it holds, nowhere else: coloring a paragraph takes time in proportion to
  /// its tokens, however much text the pane has colored before. To color rows anew, the pane has
  /// their paragraphs made anew (``recolor(rows:)``).
  ///
  /// Tokens get no color within the changed runs of a block, where the change takes precedence
  /// and the strong fill leaves too little contrast, nor within previews, which have a color of
  /// their own.
  ///
  /// - Parameter shownLength: The length of the text of the paragraph that the pane shows as it
  ///   is: before the cut of a line too long to show whole, or before its line feed.
  func color(_ paragraph: NSMutableAttributedString, at start: Int, shownLength: Int) {
    guard colorsText, shownLength > 0 else { return }
    let shown = start..<start + shownLength
    if let syntaxProvider {
      let row = grid.row(containingOffset: start)
      for (offsets, color) in syntaxRuns(inRow: row, within: shown, from: syntaxProvider) {
        paragraph.addAttribute(
          .foregroundColor, value: color, range: NSRange(offsets.shifted(by: -start)))
      }
    }
    let spans = previewSpans
    var index = spans.partitioningIndex { $0.upperBound > shown.lowerBound }
    while index < spans.count, spans[index].lowerBound < shown.upperBound {
      paragraph.addAttribute(
        .foregroundColor, value: theme.previewTextColor,
        range: NSRange(spans[index].clamped(to: shown).shifted(by: -start)))
      index += 1
    }
  }

  /// The parts of the tokens of `row` within `range` that lie outside the changed runs, each
  /// with the color of its kind.
  private func syntaxRuns(
    inRow row: Int, within range: Range<Int>, from provider: any PaneSyntaxProvider
  ) -> [(offsets: Range<Int>, color: NSColor)] {
    guard row < content.lineNumbers.count else { return [] }
    let line = content.lineNumbers[row]
    guard line >= 0 else { return [] }
    let tokens = provider.tokens(inLine: Int(line))
    guard !tokens.isEmpty else { return [] }
    let colors = Dictionary(
      uniqueKeysWithValues: PaneToken.Kind.allCases.map { ($0, theme.syntaxColor(for: $0)) })
    // Finding the changed runs of a block takes a comparison, which a row without tokens is
    // spared.
    let changedRuns = changes(inRows: row..<row + 1).runs.map(\.range)
    let rowStart = grid.offsets(ofRow: row).lowerBound
    var runs: [(offsets: Range<Int>, color: NSColor)] = []
    for token in tokens {
      // The tokens are in order, so none after one beyond the range lies within it.
      guard rowStart + token.range.lowerBound < range.upperBound else { break }
      guard let color = colors[token.kind] else { continue }
      var part = token.range.shifted(by: rowStart).clamped(to: range)
      // The changed runs are sorted, so the part loses what each takes from its start.
      for run in changedRuns where run.overlaps(part) {
        if part.lowerBound < run.lowerBound {
          runs.append((part.lowerBound..<run.lowerBound, color))
        }
        part = min(run.upperBound, part.upperBound)..<part.upperBound
      }
      if !part.isEmpty {
        runs.append((part, color))
      }
    }
    return runs
  }

  /// Colors the code of `rows` anew, after the tokens of their lines changed; all rows if `rows`
  /// is `nil`.
  func syntaxDidChange(inRows rows: Range<Int>?) {
    recolor(rows: rows)
  }

  /// Has TextKit make the paragraphs of `rows` anew, so that their text takes the colors it has
  /// now; all rows if `rows` is `nil`.
  func recolor(rows: Range<Int>?) {
    recolor([rows ?? 0..<grid.rowCount])
  }

  /// Has TextKit make the paragraphs of the rows of `ranges` anew, in one edit.
  ///
  /// TextKit lays out the rows in view again at once and the others once they come into view;
  /// that costs nothing for rows never laid out. While the text is being edited or the input
  /// method marks text, making paragraphs anew would disturb the edit or the input method, so
  /// the rows wait until it is over (``recolorWaitingRows()``), moving along with the edits.
  func recolor(_ ranges: [Range<Int>]) {
    for rows in ranges {
      rowsToRecolor.insert(integersIn: rows.clamped(to: 0..<grid.rowCount))
    }
    recolorWaitingRows()
  }

  /// Makes the paragraphs of the rows that wait to be colored anew, unless the text is being
  /// edited or the input method marks text.
  func recolorWaitingRows() {
    guard !rowsToRecolor.isEmpty, !hasMarkedText(), textStorage?.editedMask.isEmpty != false
    else { return }
    let offsets = rowsToRecolor.rangeView.compactMap { rows -> Range<Int>? in
      let rows = rows.clamped(to: 0..<grid.rowCount)
      return rows.isEmpty ? nil : grid.paragraphOffsets(ofRows: rows)
    }
    rowsToRecolor = []
    contentStorage.discardElements(in: offsets)
  }

  /// Moves the rows that wait to be colored anew along with `change`; the rows that it rewrote
  /// are made anew by the edit itself.
  func takeOverRowsToRecolor(_ change: RowChange) {
    guard !rowsToRecolor.isEmpty else { return }
    var rows = IndexSet()
    for waiting in rowsToRecolor.rangeView {
      rows.insert(integersIn: change.newRows(of: waiting))
    }
    rowsToRecolor = rows
  }
}

extension Range<Int> {
  /// The range moved by `distance`.
  fileprivate func shifted(by distance: Int) -> Range<Int> {
    lowerBound + distance..<upperBound + distance
  }
}
