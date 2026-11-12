import AppKit

/// The left margin of a pane: the line numbers, the markers of the blocks and the filled cells of
/// the current block.
///
/// The gutter sits beside the scroll view and draws the visible rows itself, each at
/// `row × rowHeight` minus the scroll offset of the text.
final class GutterView: NSView {
  var theme = Theme() {
    didSet {
      numberColumnWidth = Self.numberColumnWidth(of: content, theme: theme)
      needsDisplay = true
    }
  }

  var content = PaneContent.empty {
    didSet {
      numberColumnWidth = Self.numberColumnWidth(of: content, theme: theme)
      needsDisplay = true
    }
  }

  /// The width of the column of line numbers, which only the content and the theme change.
  private var numberColumnWidth = GutterView.numberColumnWidth(of: .empty, theme: Theme())

  var currentBlock: Int? {
    didSet { needsDisplay = true }
  }

  /// The vertical scroll offset of the text beside the gutter.
  var scrollOffset: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  /// The rows among the given ones that hold marks of removed text, which the text draws and
  /// the gutter names for VoiceOver.
  var removalRows: (Range<Int>) -> [Int] = { _ in [] }

  /// The rows that are visible beside the text.
  var visibleRows: Range<Int> {
    rows(in: bounds)
  }

  /// The rows that `rect` of the gutter shows.
  func rows(in rect: CGRect) -> Range<Int> {
    let rowHeight = theme.rowHeight
    let first = max(Int(((rect.minY + scrollOffset) / rowHeight).rounded(.down)), 0)
    let end = min(
      Int(((rect.maxY + scrollOffset) / rowHeight).rounded(.up)), content.lineNumbers.count)
    return first..<max(first, end)
  }

  /// The rectangle of `row` across the gutter.
  func rect(ofRow row: Int) -> CGRect {
    CGRect(
      x: 0, y: CGFloat(row) * theme.rowHeight - scrollOffset, width: bounds.width,
      height: theme.rowHeight)
  }

  /// The slot of the marker `index` places from the trailing edge in `rowRect`.
  func markerSlot(_ index: Int, in rowRect: CGRect) -> CGRect {
    CGRect(
      x: bounds.width - CGFloat(index + 1) * Theme.markerSlotWidth, y: rowRect.minY,
      width: Theme.markerSlotWidth, height: rowRect.height)
  }

  override var isFlipped: Bool { true }

  /// The width that the gutter needs for the widest line number and the markers of `content`.
  var fittingWidth: CGFloat {
    let width =
      Theme.gutterLeadingInset + numberColumnWidth + Theme.gutterNumberSpacing
      + CGFloat(markerSlotCount) * Theme.markerSlotWidth
    return (width / Theme.layoutGrid).rounded(.up) * Theme.layoutGrid
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // Views draw beyond their bounds unless told otherwise, and the dirty rectangle may reach
    // past them.
    clipsToBounds = true
  }

  /// Gutters are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let dirtyRect = dirtyRect.intersection(bounds)
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    let rows = rows(in: dirtyRect)
    guard !rows.isEmpty else { return }
    let numberAttributes = lineNumberAttributes(isCurrent: false)
    let currentNumberAttributes = lineNumberAttributes(isCurrent: true)
    for row in rows {
      let rowRect = rect(ofRow: row)
      let blockIndex = content.blockIndex(atRow: row)
      let isCurrent = blockIndex != nil && blockIndex == currentBlock
      if isCurrent, let blockIndex {
        let style = content.blocks[blockIndex].style
        theme.rowFill(for: style, isFiller: content.isFiller(row: row), isCurrent: true)?.setFill()
        rowRect.fill()
      }
      let lineNumber = content.lineNumbers[row]
      if lineNumber >= 0 {
        drawLineNumber(
          Int(lineNumber) + 1, in: rowRect,
          attributes: isCurrent ? currentNumberAttributes : numberAttributes)
      }
      drawMarkers(ofRow: row, blockIndex: blockIndex, in: rowRect)
    }
  }

  /// The width of the widest line number of `content`, with room for a few digits at least.
  private static func numberColumnWidth(of content: PaneContent, theme: Theme) -> CGFloat {
    let largest = content.lineNumbers.max().map { Int($0) + 1 } ?? 0
    let digits = max(String(largest).count, Theme.minimumLineNumberDigits)
    let digitWidth = ("0" as NSString).size(withAttributes: [.font: theme.lineNumberFont]).width
    return CGFloat(digits) * digitWidth
  }

  /// The number of markers that the busiest row of `content` shows side by side, at least one.
  private var markerSlotCount: Int {
    content.blocks.reduce(1) { count, block in
      max(count, (block.marker == nil ? 0 : 1) + (block.conflict == nil ? 0 : 1))
    }
  }

  private func lineNumberAttributes(isCurrent: Bool) -> [NSAttributedString.Key: Any] {
    [
      .font: theme.lineNumberFont,
      .foregroundColor: isCurrent ? Theme.currentLineNumberColor : theme.lineNumberColor,
    ]
  }

  private func drawLineNumber(
    _ number: Int, in rowRect: CGRect, attributes: [NSAttributedString.Key: Any]
  ) {
    let text = String(number) as NSString
    let size = text.size(withAttributes: attributes)
    let font = attributes[.font] as? NSFont ?? theme.lineNumberFont
    // Shares the baseline of the code beside it.
    let origin = CGPoint(
      x: Theme.gutterLeadingInset + numberColumnWidth - size.width,
      y: rowRect.minY + theme.baseline - font.ascender)
    text.draw(at: origin, withAttributes: attributes)
  }

  /// Draws the markers of `row` right-aligned in their slots: the change marker next to the text,
  /// the mark of a conflict before it, and on a row without either the ring of an
  /// ignored difference.
  private func drawMarkers(ofRow row: Int, blockIndex: Int?, in rowRect: CGRect) {
    var marks: [GutterMark] = []
    if let blockIndex, content.blocks[blockIndex].rows.lowerBound == row {
      let block = content.blocks[blockIndex]
      if let conflict = block.conflict {
        marks.append(.typed(Self.conflictCharacter, theme.color(for: conflict)))
      }
      if let marker = block.marker {
        marks.append(.typed(Self.character(for: marker), theme.markerColor(for: block.style)))
      }
    }
    if marks.isEmpty && content.ignoredDifferenceRows.contains(row) {
      marks.append(.ignoredDifference)
    }
    for (index, mark) in marks.reversed().enumerated() {
      let slot = markerSlot(index, in: rowRect)
      switch mark {
      case .typed(let character, let color):
        drawCharacter(character, color: color, centeredIn: slot)
      case .ignoredDifference:
        drawRing(centeredIn: slot)
      }
    }
  }

  /// Draws a typed mark in the code font, on the baseline of the code beside it, within a seam of
  /// background color.
  ///
  /// The seam cannot be seen on the plain gutter; on a filled cell it keeps every mark as clear
  /// as on the plain gutter, whatever the color of the cell.
  private func drawCharacter(_ character: String, color: NSColor, centeredIn slot: CGRect) {
    let text = NSAttributedString(
      string: character, attributes: [.font: theme.font, .foregroundColor: color])
    let origin = pixelAligned(
      CGPoint(
        x: slot.midX - text.size().width / 2, y: slot.minY + theme.baseline - theme.font.ascender))
    // The stroke is centered on the outline of the glyph, so half of it lies outside.
    let strokeWidth = 2 * Theme.markSeam / theme.font.pointSize * 100
    NSAttributedString(
      string: character,
      attributes: [
        .font: theme.font, .strokeColor: Theme.backgroundColor, .strokeWidth: strokeWidth,
      ]
    ).draw(at: origin)
    text.draw(at: origin)
  }

  /// Draws the hollow ring of a line whose difference the comparison ignores, within a seam of
  /// background color like the typed marks.
  private func drawRing(centeredIn slot: CGRect) {
    let ring = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    guard
      let image = ring?.withSymbolConfiguration(
        theme.ringSymbolConfiguration.applying(
          NSImage.SymbolConfiguration(paletteColors: [Theme.secondaryMarkColor]))),
      let seam = ring?.withSymbolConfiguration(
        theme.ringSymbolConfiguration.applying(
          NSImage.SymbolConfiguration(paletteColors: [Theme.backgroundColor])))
    else { return }
    let size = image.size
    let rect = CGRect(
      origin: pixelAligned(CGPoint(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2)),
      size: size)
    // The ring drawn once more, a seam wider on either side, lies below it.
    for inset in [-Theme.markSeam, 0, Theme.markSeam] {
      seam.draw(in: rect.insetBy(dx: inset, dy: inset))
    }
    image.draw(in: rect)
  }

  /// `point` moved to the nearest pixel of the screen, so that thin marks stay sharp.
  private func pixelAligned(_ point: CGPoint) -> CGPoint {
    let backing = convertToBacking(point)
    return convertFromBacking(CGPoint(x: backing.x.rounded(), y: backing.y.rounded()))
  }

  /// The typed mark of how a side changed a block.
  private static func character(for marker: Marker) -> String {
    switch marker {
    case .added: "+"
    case .changed: "~"
    case .removed: "\u{2212}"
    }
  }

  /// The typed mark of a conflict.
  private static let conflictCharacter = "!"
}

/// A mark in the gutter.
private enum GutterMark {
  /// A character in the code font: the change of a side or a conflict, in its color.
  case typed(String, NSColor)
  /// The hollow ring of a line whose difference the comparison ignores, drawn as a symbol.
  case ignoredDifference
}
