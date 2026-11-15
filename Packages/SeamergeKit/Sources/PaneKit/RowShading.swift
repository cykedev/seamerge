import AppKit

/// How a row is shaded across the full width of its pane, gutter and text alike: the fill behind
/// its text, the quieter fill of the screen lines below its text, and the hairlines at the edges
/// of changed blocks.
///
/// The text view finds the shading of each row in one place; its layout fragments and the gutter
/// both draw from it, so that the tint of a row runs from the left edge of the pane to its text
/// without a seam.
struct RowShading: Sendable {
  /// The hairlines at the top and the bottom edge of a row, each inside the row.
  struct Edges: Sendable {
    /// The color of the hairline at the top, or `nil` for none.
    var top: NSColor?
    /// The color of the hairline at the bottom, or `nil` for none.
    var bottom: NSColor?
  }

  /// The fill of the screen lines of the row's text, or `nil` for the background.
  var fill: NSColor?
  /// The fill of the screen lines of the row below its text, where a pane it lines up with wraps
  /// it more, or `nil` for the background.
  var paddingFill: NSColor?
  /// The hairlines at the edges of changed blocks in the row.
  var edges: Edges
  /// The style that the row is shaded in, which also gives the color of the cells of the current
  /// block in the gutter.
  var style: BlockStyle

  /// A row on the text background, without hairlines.
  static let plain = RowShading(fill: nil, paddingFill: nil, edges: Edges(), style: .unchanged)

  /// The thickness of a hairline in `window`: one pixel of its screen, half a point where there
  /// is no window yet.
  @MainActor static func hairline(in window: NSWindow?) -> CGFloat {
    1 / (window?.backingScaleFactor ?? 2)
  }

  /// Fills `rect`, a row of `textLines` screen lines of `rowHeight` each at the top and padding
  /// lines below, and draws its hairlines `hairline` thick at its top and bottom edge, into
  /// `context`.
  func draw(
    in rect: CGRect, textLines: Int, rowHeight: CGFloat, hairline: CGFloat, context: CGContext
  ) {
    let textHeight = min(CGFloat(max(textLines, 1)) * rowHeight, rect.height)
    let parts = [
      (fill, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: textHeight)),
      (
        paddingFill,
        CGRect(
          x: rect.minX, y: rect.minY + textHeight, width: rect.width,
          height: rect.height - textHeight)
      ),
    ]
    for (color, part) in parts {
      guard let color, !part.isEmpty else { continue }
      context.setFillColor(color.cgColor)
      context.fill(part)
    }
    drawEdges(in: rect, hairline: hairline, context: context)
  }

  /// Draws the hairlines of the row of `rect`, `hairline` thick, into `context`.
  func drawEdges(in rect: CGRect, hairline: CGFloat, context: CGContext) {
    for (color, y) in [(edges.top, rect.minY), (edges.bottom, rect.maxY - hairline)] {
      guard let color else { continue }
      context.setFillColor(color.cgColor)
      context.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: hairline))
    }
  }
}
