import AppKit

/// The bar of toggles of one block as the decision column draws it: a capsule of three equal
/// segments, A, the base and B, parted by hairlines, in the slots of ``DecisionColumnLayout``.
///
/// A segment whose input is not taken shows its sign alone, quiet; one that the merge took is
/// lightly tinted in the color of its side, with its sign in that color; one that the user chose
/// is filled in that color. The sign is the letter of A or B, a ring for the base, and a trash
/// can for a side that removed the lines. While the block is an open conflict, the whole bar is
/// tinted red and outlined in red, the outline dashed where marks must differ in shape too.
@MainActor
struct DecisionBar {
  /// One segment of the bar.
  struct Segment {
    var slot: DecisionColumnLayout.Slot
    var role: ColorRole
    var face: DecisionToggleButton.Face
    /// Whether taking the input removes the lines of the block.
    var removesLines: Bool
  }

  /// The segments of the inputs that take part, in any order.
  var segments: [Segment]

  /// Whether the block is a conflict that awaits a decision.
  var isOpenConflict: Bool

  /// The colors of the column.
  var theme: Theme

  /// Where the parts of the row stand, for the rows of the text of `theme`.
  var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: theme)
  }

  /// Draws the bar into the row of its block, with its edges on whole pixels at `scale`.
  func draw(at scale: CGFloat) {
    let bar = layout.barRect
    let capsule = NSBezierPath(
      roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
    if isOpenConflict,
      let tint = theme.rowFill(for: .tinted(.conflict), isFiller: false, isCurrent: false)
    {
      tint.setFill()
      capsule.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    capsule.addClip()
    for segment in segments {
      guard let fill = fill(for: segment) else { continue }
      fill.setFill()
      segmentRect(of: segment.slot).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let hairline = 1 / scale
    theme.toggleSeparatorColor.setFill()
    for slot in [DecisionColumnLayout.Slot.base, .b] {
      let x = layout.frame(of: slot).minX
      CGRect(x: x - hairline, y: bar.minY, width: hairline, height: bar.height).fill()
    }
    drawOutline(of: bar, at: scale)
    for segment in segments {
      drawSign(of: segment, at: scale)
    }
  }

  /// The part of the bar that the segment in `slot` covers.
  private func segmentRect(of slot: DecisionColumnLayout.Slot) -> CGRect {
    let bar = layout.barRect
    let frame = layout.frame(of: slot)
    return CGRect(x: frame.minX, y: bar.minY, width: frame.width, height: bar.height)
  }

  /// The fill of `segment`: the color of its side where chosen, the tint of the rows of its side
  /// where the merge took it, none where it is off.
  private func fill(for segment: Segment) -> NSColor? {
    switch segment.face {
    case .off: nil
    case .automatic:
      theme.rowFill(for: Self.style(of: segment.role), isFiller: false, isCurrent: true)
    case .chosen: theme.chosenFill(for: segment.role)
    }
  }

  /// The color of the sign of `segment` on its fill.
  private func signColor(of segment: Segment) -> NSColor {
    switch segment.face {
    case .off: theme.offToggleLabelColor
    case .automatic: theme.symbolColor(for: segment.role)
    case .chosen: theme.chosenSignColor(for: segment.role)
    }
  }

  /// Draws the outline of the bar within its edge, so that every bar has the same contour: a
  /// hairline as strong as the edges of the blocks, which an open conflict draws red and thicker
  /// inwards, dashed where marks must differ in shape too, on top of the hairline that keeps the
  /// contour whole.
  private func drawOutline(of bar: CGRect, at scale: CGFloat) {
    func stroke(width: CGFloat, color: NSColor, dashed: Bool = false) {
      // The line is centered on the path, so the path lies half its width inside the edge.
      let inset = bar.insetBy(dx: width / 2, dy: width / 2)
      let outline = NSBezierPath(
        roundedRect: inset, xRadius: inset.height / 2, yRadius: inset.height / 2)
      outline.lineWidth = width
      if dashed {
        outline.setLineDash(
          Theme.openConflictOutlineDash, count: Theme.openConflictOutlineDash.count, phase: 0)
      }
      color.setStroke()
      outline.stroke()
    }
    let isDashed = isOpenConflict && theme.differentiatesWithoutColor
    stroke(
      width: 1 / scale,
      color: isOpenConflict && !isDashed
        ? theme.symbolColor(for: .conflict) : theme.toggleOutlineColor)
    guard isOpenConflict else { return }
    stroke(
      width: max((Theme.openConflictOutlineWidth * scale).rounded(), 1) / scale,
      color: theme.symbolColor(for: .conflict), dashed: isDashed)
  }

  /// Draws the sign of `segment` in the middle of its part of the bar: the trash can where its
  /// side removed the lines, a ring for the base, or else the letter.
  private func drawSign(of segment: Segment, at scale: CGFloat) {
    let rect = segmentRect(of: segment.slot)
    let color = signColor(of: segment)
    let font = Self.font(of: layout)
    let symbol: NSImage? =
      if segment.removesLines {
        Self.symbol(
          "trash", pointSize: font.pointSize - Theme.trashSymbolSizeReduction, scale: .small,
          color: color)
      } else if segment.role == .base {
        Self.symbol(
          "circle", pointSize: font.pointSize - Theme.baseSymbolSizeReduction, scale: .medium,
          color: color)
      } else {
        nil
      }
    if let symbol {
      let size = symbol.size
      // A sign stands on the capitals of the letters beside it: its alignment rectangle, whose
      // origin is at the bottom, spans from the baseline to the capitals. Like the letters, it
      // is left where it lies between pixels: its ink is smoothed.
      let middleFromTop = size.height - symbol.alignmentRect.midY
      symbol.draw(
        in: CGRect(
          x: ((rect.midX - size.width / 2) * scale).rounded() / scale,
          y: rect.midY - middleFromTop, width: size.width, height: size.height))
      return
    }
    let label = NSAttributedString(
      string: DecisionToggleButton.name(of: segment.role),
      attributes: [.font: font, .foregroundColor: color])
    // Centered on the capitals, which leave more room above them than below for accents; without
    // the line fragment option, the origin of the rectangle is the baseline.
    let width = label.size().width
    label.draw(
      with: CGRect(
        x: ((rect.midX - width / 2) * scale).rounded() / scale,
        y: rect.midY + font.capHeight / 2, width: width, height: font.ascender - font.descender),
      options: [])
  }

  /// The tint that the rows of `role` take.
  private static func style(of role: ColorRole) -> BlockStyle {
    role == .base ? .original : .tinted(role)
  }

  /// The symbol `name` at `pointSize` and `scale` in the weight of the letters, in `color`.
  private static func symbol(
    _ name: String, pointSize: CGFloat, scale: NSImage.SymbolScale, color: NSColor
  ) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium, scale: scale)
          .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
  }

  /// The font of the letters on a bar of `layout`.
  static func font(of layout: DecisionColumnLayout) -> NSFont {
    .systemFont(ofSize: layout.letterSize, weight: .medium)
  }
}
