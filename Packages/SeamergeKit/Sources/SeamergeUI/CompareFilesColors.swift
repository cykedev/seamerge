import AppKit

/// The colors of the window Compare Files, made from the system's label and fill colors so that
/// they follow the appearance and the contrast setting.
///
/// Text that is quieter than the file names still reaches 4.5 : 1 on the window and on a filled
/// field; `secondaryLabelColor` reaches only 3.9 : 1 in the light appearance.
struct CompareFilesColors {
  /// The color of quiet text: the invitation of an empty field, the folders, the roles below the
  /// fields and the heading of the recent comparisons.
  let quietText: NSColor

  /// The border of an empty field, which must stand out from the window at 3 : 1.
  let emptyFieldBorder = NSColor.secondaryLabelColor

  /// The border of a filled field, whose fill already sets it apart.
  let filledFieldBorder = NSColor.separatorColor

  /// The fill of a filled field.
  let filledFieldFill = NSColor.quaternarySystemFill

  /// The border of a field that a drop would fill: the color the system draws the focus with.
  let dropTargetBorder = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(1)

  /// The colors with `options`, which raise the contrast of quiet text when the system asks for
  /// it.
  init(_ options: DisplayOptions) {
    let opacity: CGFloat = options.increasesContrast ? 0.75 : 0.6
    quietText = NSColor(name: nil) { appearance in
      var label = NSColor.labelColor
      appearance.performAsCurrentDrawingAppearance {
        label = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
      }
      return label.withAlphaComponent(opacity)
    }
  }
}
