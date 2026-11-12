import AppKit

extension PaneTextView {
  /// The offsets of the previews, those next to each other joined, each with the line ending of
  /// its last line.
  var previewSpans: [Range<Int>] {
    if let cachedPreviewSpans {
      return cachedPreviewSpans
    }
    var spans: [Range<Int>] = []
    for range in content.previews.map(\.range) {
      if let last = spans.last, last.upperBound == range.lowerBound {
        spans[spans.count - 1] = last.lowerBound..<range.upperBound
      } else {
        spans.append(range)
      }
    }
    cachedPreviewSpans = spans
    return spans
  }

  /// The rows of each preview with its side.
  func previewRows() -> [(rows: Range<Int>, role: ColorRole)] {
    if let cachedPreviewRows {
      return cachedPreviewRows
    }
    let previewRows = content.previews.map { preview in
      let first = grid.row(containingOffset: preview.range.lowerBound)
      let last = grid.row(containingOffset: preview.range.upperBound - 1)
      return (rows: first..<last + 1, role: preview.role)
    }
    cachedPreviewRows = previewRows
    return previewRows
  }

  /// How `row` is tinted: in the color of the side whose preview it shows, otherwise like its
  /// block.
  func style(ofRow row: Int) -> BlockStyle {
    if let preview = previewRows().first(where: { $0.rows.contains(row) }) {
      return .tinted(preview.role)
    }
    return content.blockIndex(atRow: row).map { content.blocks[$0].style } ?? .unchanged
  }

  /// Keeps the insertion point and the ends of every selection out of the previews, which cannot
  /// be entered, whichever way the selection was made: mouse, keys, Select All, find or
  /// VoiceOver.
  ///
  /// An insertion point that would land in a preview skips it in the direction it moved: to the
  /// line after it when it moved forward, to the end of the line before it when it moved back.
  /// The end of a selection that moved into a preview takes in the whole preview, or stops before
  /// it when the selection shrinks.
  override func setSelectedRanges(
    _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
  ) {
    guard !previewSpans.isEmpty else {
      return super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }
    let previous = selectedRanges.map(\.rangeValue)
    let adjusted = ranges.enumerated().map { index, value in
      let range = value.rangeValue
      let before = index < previous.count ? previous[index] : previous.first ?? range
      return NSValue(range: rangeOutsidePreviews(range, before: before))
    }
    super.setSelectedRanges(adjusted, affinity: affinity, stillSelecting: stillSelecting)
  }

  /// `range` with its ends moved out of the previews, given the range it was before.
  private func rangeOutsidePreviews(_ range: NSRange, before: NSRange) -> NSRange {
    guard range.location != NSNotFound else { return range }
    if range.length == 0 {
      return NSRange(location: insertionPoint(range.location, from: before.location), length: 0)
    }
    var start = range.location
    var end = range.location + range.length
    if let span = span(entering: start) {
      start = start < before.location ? span.lowerBound : span.upperBound
    }
    if let span = previewSpans.first(where: { $0.lowerBound < end && end < $0.upperBound }) {
      end = end > before.location + before.length ? span.upperBound : span.lowerBound
    }
    guard start < end else {
      return NSRange(location: insertionPoint(start, from: before.location), length: 0)
    }
    return NSRange(location: start, length: end - start)
  }

  /// Where an insertion point that moved from `previous` to `offset` comes to rest outside the
  /// previews.
  private func insertionPoint(_ offset: Int, from previous: Int) -> Int {
    guard let span = span(entering: offset) else { return offset }
    guard offset < previous else { return span.upperBound }
    // Back to the text before the preview: on its own line, the end of the line before.
    if !startsRow(span.lowerBound) { return span.lowerBound }
    return span.lowerBound > 0 ? span.lowerBound - 1 : span.upperBound
  }

  /// The joined previews that a place at `offset` lies within, or `nil` if it lies outside them.
  ///
  /// A place at the start of a preview lies within it if the preview starts a row, where the
  /// place shows at the start of its first line; after text on the same row, it lies before it.
  private func span(entering offset: Int) -> Range<Int>? {
    previewSpans.first { span in
      (span.lowerBound < offset && offset < span.upperBound)
        || (offset == span.lowerBound && startsRow(offset))
    }
  }

  /// Whether `offset` is the start of a row.
  private func startsRow(_ offset: Int) -> Bool {
    grid.offsets(ofRow: grid.row(containingOffset: offset)).lowerBound == offset
  }

  /// Gives the text of the previews its color as TextKit draws it, while there are previews.
  ///
  /// Without previews, TextKit is spared asking for the color of each paragraph it draws.
  func validatesPreviewColor(_ validates: Bool) {
    guard let textLayoutManager else { return }
    guard validates else {
      textLayoutManager.renderingAttributesValidator = nil
      return
    }
    textLayoutManager.renderingAttributesValidator = { [weak self] _, fragment in
      // AppKit lays out and draws text views on the main thread.
      MainActor.assumeIsolated { self?.validatePreviewColor(of: fragment) }
    }
  }

  /// Draws the text of the previews in `fragment` in the preview color, which marks it as a
  /// preview rather than text of the file.
  ///
  /// The color is a rendering attribute, so that it is neither part of the text nor passed on to
  /// text typed next to a preview.
  private func validatePreviewColor(of fragment: NSTextLayoutFragment) {
    guard !previewSpans.isEmpty || hasColoredPreviews, let textLayoutManager,
      let range = fragment.textElement?.elementRange
    else { return }
    let documentStart = textLayoutManager.documentRange.location
    applyPreviewColor(
      in: textLayoutManager.offset(
        from: documentStart, to: range.location)..<textLayoutManager
        .offset(from: documentStart, to: range.endLocation))
  }

  /// Gives the text of the previews within `range` the preview color, and the rest of it none.
  ///
  /// Invalidating the rendering attributes of text, as each new drawing of its rows does, takes
  /// the color away without asking for it again, so the pane gives it again right after.
  func applyPreviewColor(in range: Range<Int>) {
    // Without previews, now or before, there is no color to give or take.
    guard let textLayoutManager, !range.isEmpty, !previewSpans.isEmpty || hasColoredPreviews
    else { return }
    hasColoredPreviews = !previewSpans.isEmpty
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
    for span in previewSpans where span.overlaps(range) {
      guard let previewRange = textRange(span.clamped(to: range)) else { continue }
      textLayoutManager.setRenderingAttributes(
        [.foregroundColor: theme.previewTextColor], for: previewRange)
    }
  }

  /// Cross-fades the text from how it looks now to how it looks once the change under way has
  /// been drawn: a preview turning into text, or text into a preview.
  ///
  /// A cross-fade moves nothing, so it stays with Reduce Motion.
  func fadeAfterPreviewChange() {
    guard window != nil, let layer = enclosingScrollView?.contentView.layer else { return }
    let transition = CATransition()
    transition.type = .fade
    transition.duration = Theme.previewFadeDuration
    layer.add(transition, forKey: Self.previewFadeKey)
  }

  /// The key of the cross-fade in the animations of the layer it runs on.
  static let previewFadeKey = "previewFade"
}
