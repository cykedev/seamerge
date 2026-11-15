import AppKit

extension RowLayoutFragment {
  /// Draws a symbol in the cell of each space and tab of the fragment's lines and one for the
  /// ending of each line after its last character, or only in the cells of the spaces and tabs
  /// in places of ignored differences.
  ///
  /// The symbols are drawn only, never part of the text, so that they are neither copied nor
  /// read by VoiceOver.
  func drawInvisibles(
    _ invisibles: Invisibles, at point: CGPoint, in context: CGContext, carets: [LineCarets]
  ) {
    // The symbols take the font of the text around them.
    guard
      let text = textLineFragments.first(where: { $0.attributedString.length > 0 })?
        .attributedString,
      let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    else { return }
    let symbols = Symbols(font: font, color: invisibles.color)
    let placeSymbols = Symbols(font: font, color: invisibles.placeColor)
    let showsAll = invisibles.lineEndings != nil
    context.saveGState()
    defer { context.restoreGState() }
    // The context is flipped; text needs its own matrix to stand upright.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    let lines = textLineFragments
    for (lineIndex, line) in lines.enumerated() {
      let row = rowIndex(of: line)
      // The ending of a row follows the last of its lines.
      let isLastOfRow = lineIndex + 1 == lines.count || rowIndex(of: lines[lineIndex + 1]) != row
      let text = line.attributedString.string as NSString
      let range = line.characterRange
      let baseline = point.y + CGFloat(lineIndex) * rowHeight + invisibles.baseline
      func cellStart(_ index: Int) -> CGFloat {
        point.x + line.typographicBounds.minX + carets[lineIndex].x(at: index)
      }
      var end = range.upperBound
      if end > range.lowerBound && text.character(at: end - 1) == Self.lineFeed {
        end -= 1
      }
      for index in range.lowerBound..<end {
        let character = text.character(at: index)
        guard character == Self.space || character == Self.tab else { continue }
        let isInPlace = Self.contains(invisibles.places, paragraphStart + index)
        guard isInPlace || showsAll else { continue }
        let set = isInPlace ? placeSymbols : symbols
        draw(
          character == Self.space ? set.space : set.tab, x: cellStart(index), baseline: baseline,
          in: context)
      }
      if isLastOfRow, let lineEndings = invisibles.lineEndings, row < lineEndings.count,
        let ending = symbols.lineEnding(lineEndings[row])
      {
        draw(ending, x: cellStart(end), baseline: baseline, in: context)
      }
    }
  }

  /// Whether one of `places`, sorted and apart, contains `offset`.
  private static func contains(_ places: [Range<Int>], _ offset: Int) -> Bool {
    let index = places.partitioningIndex { $0.upperBound > offset }
    return index < places.count && places[index].contains(offset)
  }

  private func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat, in context: CGContext) {
    context.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line, context)
  }

  private static let space: unichar = 0x20
  private static let tab: unichar = 0x09
  private static let lineFeed: unichar = 0x0A

  /// The symbols, set once for each drawing.
  private struct Symbols {
    let space: CTLine
    let tab: CTLine
    let endings: [LineEnding: CTLine]

    init(font: NSFont, color: NSColor) {
      func line(_ string: String) -> CTLine {
        CTLineCreateWithAttributedString(
          NSAttributedString(
            string: string,
            attributes: [
              .font: font,
              NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            ]))
      }
      space = line("·")
      tab = line("→")
      endings = Dictionary(
        uniqueKeysWithValues: LineEnding.allCases.filter { $0 != .none }.map {
          ($0, line($0.symbol))
        })
    }

    func lineEnding(_ ending: LineEnding) -> CTLine? {
      endings[ending]
    }
  }
}
