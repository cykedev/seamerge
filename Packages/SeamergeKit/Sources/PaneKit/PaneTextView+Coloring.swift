import AppKit

extension PaneTextView {
  /// Whether some text of the pane has a color of its own: previews, or code colored by its
  /// syntax.
  private var colorsText: Bool { !previewSpans.isEmpty || syntaxProvider != nil }

  /// Lets TextKit ask the pane for the colors of the text it lays out, while some text has a
  /// color of its own.
  ///
  /// Without such text, TextKit is spared asking for the colors of each paragraph it draws.
  func updateTextColorValidation() {
    guard let textLayoutManager else { return }
    guard colorsText else {
      textLayoutManager.renderingAttributesValidator = nil
      return
    }
    // A validator set anew would make TextKit validate every fragment again.
    guard textLayoutManager.renderingAttributesValidator == nil else { return }
    textLayoutManager.renderingAttributesValidator = { [weak self] _, fragment in
      // AppKit lays out and draws text views on the main thread.
      MainActor.assumeIsolated { self?.validateTextColors(of: fragment) }
    }
  }

  /// Gives the text in `fragment` its colors.
  private func validateTextColors(of fragment: NSTextLayoutFragment) {
    guard colorsText || hasColoredText, let textLayoutManager,
      let range = fragment.textElement?.elementRange
    else { return }
    let documentStart = textLayoutManager.documentRange.location
    applyTextColors(
      in: textLayoutManager.offset(
        from: documentStart, to: range.location)..<textLayoutManager
        .offset(from: documentStart, to: range.endLocation))
  }

  /// The offsets of the text that TextKit has laid out for the visible part of the view, or
  /// `nil` if it has laid out none.
  private var viewportOffsets: Range<Int>? {
    guard let textLayoutManager,
      let viewport = textLayoutManager.textViewportLayoutController.viewportRange
    else { return nil }
    let documentStart = textLayoutManager.documentRange.location
    return textLayoutManager.offset(
      from: documentStart, to: viewport.location)..<textLayoutManager.offset(
        from: documentStart, to: viewport.endLocation)
  }

  /// Gives the text within `range` its colors: the previews the preview color, the tokens of
  /// the syntax provider within `syntaxRange` theirs, and the rest of it none.
  ///
  /// The colors are rendering attributes, so that they are neither part of the text nor passed
  /// on to text typed next to them. Invalidating the rendering attributes of text, as each new
  /// drawing of its rows does, takes the colors away without asking for them again, so the pane
  /// gives them again right after.
  ///
  /// Tokens get no color within the changed runs of a block, where the change takes precedence
  /// and the strong fill leaves too little contrast, nor within previews, which have a color of
  /// their own.
  ///
  /// - Parameter syntaxRange: Where tokens get their colors; by default all of `range`.
  func applyTextColors(in range: Range<Int>, syntaxIn syntaxRange: Range<Int>? = nil) {
    // Without colored text, now or before, there is no color to give or take.
    guard let textLayoutManager, !range.isEmpty, colorsText || hasColoredText else { return }
    hasColoredText = colorsText
    let documentStart = textLayoutManager.documentRange.location
    func textRange(_ offsets: Range<Int>) -> NSTextRange? {
      guard
        let start = textLayoutManager.location(documentStart, offsetBy: offsets.lowerBound),
        let end = textLayoutManager.location(documentStart, offsetBy: offsets.upperBound)
      else { return nil }
      return NSTextRange(location: start, end: end)
    }
    guard let whole = textRange(range) else { return }
    textLayoutManager.removeRenderingAttribute(.foregroundColor, for: whole)
    let syntaxRange = (syntaxRange ?? range).clamped(to: range)
    if let syntaxProvider, !syntaxRange.isEmpty {
      for (offsets, color) in syntaxRuns(in: syntaxRange, from: syntaxProvider) {
        guard let tokenRange = textRange(offsets) else { continue }
        textLayoutManager.addRenderingAttribute(.foregroundColor, value: color, for: tokenRange)
      }
    }
    for span in previewSpans where span.overlaps(range) {
      guard let previewRange = textRange(span.clamped(to: range)) else { continue }
      textLayoutManager.setRenderingAttributes(
        [.foregroundColor: theme.previewTextColor], for: previewRange)
    }
  }

  /// The parts of the tokens within `range` that lie outside the changed runs, each with the
  /// color of its kind.
  private func syntaxRuns(
    in range: Range<Int>, from provider: any PaneSyntaxProvider
  ) -> [(offsets: Range<Int>, color: NSColor)] {
    let colors = Dictionary(
      uniqueKeysWithValues: PaneToken.Kind.allCases.map { ($0, theme.syntaxColor(for: $0)) })
    let rows =
      grid.row(containingOffset: range.lowerBound)..<grid.row(
        containingOffset: range.upperBound - 1) + 1
    var runs: [(offsets: Range<Int>, color: NSColor)] = []
    for row in rows where row < content.lineNumbers.count {
      let line = content.lineNumbers[row]
      guard line >= 0 else { continue }
      let tokens = provider.tokens(inLine: Int(line))
      guard !tokens.isEmpty else { continue }
      // Finding the changed runs of a block takes a comparison, which a row without tokens is
      // spared.
      let changedRuns = changes(inRows: row..<row + 1).runs.map(\.range)
      let rowOffsets = grid.offsets(ofRow: row)
      let visible = rowOffsets.clamped(to: range)
      for token in tokens {
        guard let color = colors[token.kind] else { continue }
        var part =
          (rowOffsets.lowerBound + token.range.lowerBound..<rowOffsets.lowerBound
          + token.range.upperBound).clamped(to: visible)
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
    }
    return runs
  }

  /// Colors the code of `rows` anew, after the tokens of their lines changed; all rows if `rows`
  /// is `nil`.
  ///
  /// Rows in view get their colors at once. TextKit asks for the colors of a paragraph only when
  /// it first lays it out, so the pane discards what TextKit holds of the rows out of view, which
  /// get their colors once they are laid out again; that costs nothing for rows never laid out.
  func syntaxDidChange(inRows rows: Range<Int>?) {
    updateTextColorValidation()
    let rows = (rows ?? 0..<grid.rowCount).clamped(to: 0..<grid.rowCount)
    guard !rows.isEmpty else { return }
    let offsets = grid.paragraphOffsets(ofRows: rows)
    var inView = viewportOffsets.map { offsets.clamped(to: $0) } ?? offsets
    if inView.isEmpty {
      inView = offsets.lowerBound..<offsets.lowerBound
    }
    for part in [offsets.lowerBound..<inView.lowerBound, inView.upperBound..<offsets.upperBound]
    where !part.isEmpty {
      if hasMarkedText() || textStorage?.editedMask.isEmpty == false {
        // Discarding would disturb the input method or the edit under way.
        applyTextColors(in: part)
      } else {
        contentStorage.discardElements(in: part)
      }
    }
    guard !inView.isEmpty else { return }
    redraw(
      rows: grid.row(containingOffset: inView.lowerBound)..<grid.row(
        containingOffset: inView.upperBound - 1) + 1)
  }
}
