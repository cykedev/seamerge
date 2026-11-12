import AppKit

/// The fonts, metrics and colors that the panes are drawn with.
///
/// Every color adapts to the appearance it is drawn in: light, dark, and both with increased
/// contrast. Neutral colors are the dynamic system colors; only the role colors have fixed values.
public struct Theme {
  /// The font of the code, a font of fixed width.
  public var font: NSFont

  /// The height of a row as a multiple of the font size.
  public var lineHeightMultiple: CGFloat

  /// The width of a tab, in characters.
  public var tabWidth: Int

  /// Whether the colors take their values for increased contrast.
  ///
  /// Set it from the system setting, `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`.
  /// The colors also take those values in an appearance that has increased contrast.
  public var increasesContrast: Bool

  /// Whether marks that differ in color differ in shape as well.
  ///
  /// Set it from the system setting,
  /// `NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor`. Open conflicts in the
  /// overview bar then get a notch at their leading edge.
  public var differentiatesWithoutColor: Bool

  /// Creates a theme.
  public init(
    font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
    lineHeightMultiple: CGFloat = 1.5,
    tabWidth: Int = 4,
    increasesContrast: Bool = false,
    differentiatesWithoutColor: Bool = false
  ) {
    self.font = font
    self.lineHeightMultiple = lineHeightMultiple
    self.tabWidth = tabWidth
    self.increasesContrast = increasesContrast
    self.differentiatesWithoutColor = differentiatesWithoutColor
  }

  /// The height of every row, in points: the font size times the multiple, rounded up.
  public var rowHeight: CGFloat {
    (font.pointSize * lineHeightMultiple).rounded(.up)
  }

  /// The font of the line numbers: two points smaller than the code, but never below the
  /// smallest size of the interface, with digits of equal width.
  public var lineNumberFont: NSFont {
    .monospacedDigitSystemFont(
      ofSize: max(font.pointSize - 2, Self.smallestFontSize), weight: .regular)
  }

  /// The size and weight of the ring of an ignored difference in the gutter.
  var ringSymbolConfiguration: NSImage.SymbolConfiguration {
    NSImage.SymbolConfiguration(
      pointSize: lineNumberFont.pointSize, weight: .medium, scale: .small)
  }

  /// The width of one character of the code font.
  var characterWidth: CGFloat {
    ("0" as NSString).size(withAttributes: [.font: font]).width
  }

  /// How far the text is raised so that it sits in the middle of its row.
  ///
  /// TextKit puts the baseline as low as the font's descent allows and leaves the room that a
  /// row has beyond the font's height above the glyphs. Raising the text by half that room
  /// centers it; the fragments draw it raised, while selection and row stay where they are.
  var textLift: CGFloat {
    ((rowHeight + font.descender - font.ascender) / 2).rounded()
  }

  /// The distance from the top of a row to the baseline of its text, as drawn.
  var baseline: CGFloat {
    (rowHeight + font.descender).rounded(.down) - textLift
  }

  /// The height of the band of a line's text, centered in the row like the text: the height of
  /// the highlights of changed runs and of the marks of removed text.
  var textBandHeight: CGFloat {
    min((font.ascender - font.descender).rounded(.up), rowHeight)
  }

  /// The distance from the left edge of the text area to the text, and from the longest line to
  /// the right edge.
  static let textInset: CGFloat = 12

  /// The distance from the left edge of the gutter to the widest line number.
  static let gutterLeadingInset: CGFloat = 8

  /// The distance between the line numbers and the first marker slot.
  static let gutterNumberSpacing: CGFloat = 4

  /// The width of the slot that one gutter marker is centered in.
  static let markerSlotWidth: CGFloat = 16

  /// The number of digits that the line numbers have room for even in short files, so that the
  /// text does not shift sideways between panes of different lengths.
  static let minimumLineNumberDigits = 3

  /// The width of the mark where a side removed text within a line: wider than the insertion
  /// point, too narrow to read as a character.
  static let removalMarkWidth: CGFloat = 2

  /// The width of the seam of background color around the marks in the gutter and the mark of
  /// removed text, which keeps them clear on a selection or a cell of a similar color.
  static let markSeam: CGFloat = 1

  /// The grid that widths and distances of the panes are rounded to.
  static let layoutGrid: CGFloat = 4

  /// The number of characters that a pane shows at its minimum width.
  static let minimumTextColumns = 20

  /// The number of characters that stay visible before a place that the pane scrolls to.
  static let revealContextColumns = 8

  /// Where the reading line lies, as a fraction of the visible height from the top: the line
  /// that panes coupled by blocks align, and where a place that the pane scrolls to comes to
  /// rest.
  static let readingLine: CGFloat = 0.25

  /// The width of the overview bar.
  static let overviewBarWidth: CGFloat = 12

  /// The distance between the edges of the overview bar and its marks.
  static let overviewMarkInset: CGFloat = 2

  /// The smallest height of a mark in the overview bar, so that a single line stays visible and
  /// can be clicked in a long file.
  static let overviewMarkMinimumHeight: CGFloat = 3

  /// How far beyond a mark in the overview bar a click still hits it.
  static let overviewMarkHitSlop: CGFloat = 3

  /// The height of the triangle that points at the current block in the overview bar.
  static let currentBlockIndicatorHeight: CGFloat = 6

  /// The width of the notch of an open conflict in the overview bar.
  static let conflictNotchWidth: CGFloat = 2

  /// The smallest font size of the interface.
  private static let smallestFontSize: CGFloat = 10
}
