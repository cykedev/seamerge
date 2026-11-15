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

  /// Whether a preview turns into text at once rather than in a cross-fade.
  ///
  /// Set it from the system setting, `NSWorkspace.accessibilityDisplayShouldReduceMotion`.
  public var reducesMotion: Bool

  /// Creates a theme.
  public init(
    font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
    lineHeightMultiple: CGFloat = 1.5,
    tabWidth: Int = 4,
    increasesContrast: Bool = false,
    differentiatesWithoutColor: Bool = false,
    reducesMotion: Bool = false
  ) {
    self.font = font
    self.lineHeightMultiple = lineHeightMultiple
    self.tabWidth = tabWidth
    self.increasesContrast = increasesContrast
    self.differentiatesWithoutColor = differentiatesWithoutColor
    self.reducesMotion = reducesMotion
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

  /// How many columns the screen lines after the first of a wrapped row are indented beyond the
  /// indentation of the row, so that the eye sees that the row goes on.
  static let continuationIndentColumns = 2

  /// The most columns of a row's indentation that its screen lines after the first follow, so
  /// that they keep room for text even in a narrow pane.
  static let maximumFollowedIndentColumns = 16

  /// How far the screen lines after the first of a wrapped row are indented, given the columns of
  /// spaces and tabs that the row starts with.
  func continuationIndent(afterIndentationOf columns: Int) -> CGFloat {
    let followed = min(columns, Self.maximumFollowedIndentColumns)
    return CGFloat(followed + Self.continuationIndentColumns) * characterWidth
  }

  /// The number of characters that stay visible before a place that the pane scrolls to.
  static let revealContextColumns = 8

  /// Where the reading line lies, as a fraction of the visible height from the top: the line
  /// that panes coupled by blocks align, and where a place that the pane scrolls to comes to
  /// rest.
  public static let readingLine: CGFloat = 0.25

  /// The width of the seam between two panes that connect their changes with bands: room for a
  /// band to turn, and a target for dragging the divider below it.
  public static let seamWidth: CGFloat = 28

  /// The width of the outline of a match of the search in the text.
  static let searchMatchOutlineWidth: CGFloat = 1.5

  /// The corner radius of the outline of a match of the search in the text.
  static let searchMatchCornerRadius: CGFloat = 3

  /// The width of the overview bar.
  static let overviewBarWidth: CGFloat = 12

  /// The distance between the edges of the overview bar and its marks.
  static let overviewMarkInset: CGFloat = 2

  /// The smallest height of a mark in the overview bar, so that a single line stays visible and
  /// can be clicked in a long file.
  static let overviewMarkMinimumHeight: CGFloat = 3

  /// How far beyond a mark in the overview bar a click still hits it.
  static let overviewMarkHitSlop: CGFloat = 3

  /// The width of the outline of the frame that shows the visible part in the overview bar.
  static let visibleRegionOutlineWidth: CGFloat = 1

  /// The radius of the corners of the frame that shows the visible part in the overview bar.
  static let visibleRegionCornerRadius: CGFloat = 3

  /// The height of the triangle that points at the current block in the overview bar.
  static let currentBlockIndicatorHeight: CGFloat = 6

  /// The width of the notch of an open conflict in the overview bar.
  static let conflictNotchWidth: CGFloat = 2

  /// The text style of the label on the bar of a collapsed run.
  static let collapsedRunTextStyle: NSFont.TextStyle = .subheadline

  /// The distance between the ellipsis on the bar of a collapsed run and its label.
  static let collapsedRunSymbolSpacing: CGFloat = 4

  /// The height of the toggles and the reset arrow in the decision column, and the smallest width
  /// of each: the smallest target that a click needs.
  static let decisionControlSize: CGFloat = 20

  /// The distance between the edges of the decision column and what it shows.
  static let decisionColumnInset: CGFloat = 4

  /// How much lower the bar of toggles is than a row of the text, so that the bars of blocks on
  /// lines one after the other keep this gap.
  static let toggleBarGap: CGFloat = 2

  /// How high the bar of toggles is at least and at most, whatever the rows of the text.
  static let toggleBarHeights: ClosedRange<CGFloat> = 14...20

  /// How much wider each segment of the bar of toggles is than the bar is high.
  static let toggleSegmentPadding: CGFloat = 2

  /// The size of the letters of the bar of toggles to its height: 11 points on a bar of 18.
  static let toggleLetterRatio: CGFloat = 11 / 18

  /// The distance between the bar of toggles and the place for the reset arrow beside it.
  static let decisionPlaceGap: CGFloat = 4

  /// The radius of the corners of the reset arrow while it is pressed or has the focus.
  static let resetCornerRadius: CGFloat = 5

  /// How much smaller the trash can of a side that removes the lines is than the letters, at
  /// the small scale of symbols, so that the can stands as high as their capitals.
  static let trashSymbolSizeReduction: CGFloat = 2

  /// How much smaller the ring that stands for the base is than the letters, so that it looks
  /// as large as the capitals beside it.
  static let baseSymbolSizeReduction: CGFloat = 2

  /// The width of the red outline of the bar of an open conflict.
  static let openConflictOutlineWidth: CGFloat = 1.5

  /// The dashes of the outline of an open conflict where marks also differ in shape: dash and
  /// gap, in points.
  static let openConflictOutlineDash: [CGFloat] = [3, 2]

  /// How long a preview takes to turn into text, or text into a preview.
  static let previewFadeDuration: CFTimeInterval = 0.15

  /// The smallest font size of the interface.
  static let smallestFontSize: CGFloat = 10
}
