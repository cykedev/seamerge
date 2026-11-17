import AppKit
import PaneKit

/// The colors of the sheets of files and of the other sheets of the welcome window, made from the
/// system's label and fill colors so that they follow the appearance and the contrast setting.
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

  /// The border of a field that a drop would fill: the focus color, darkened or lightened as far
  /// as it takes to stand out from the window at 3 : 1.
  let dropTargetBorder: NSColor

  /// The colors with `options`, which raise the contrast of quiet text when the system asks for
  /// it.
  ///
  /// - Parameter focusColor: The color the system draws the focus with, which follows the accent
  ///   color the user chose.
  init(_ options: DisplayOptions, focusColor: NSColor = .keyboardFocusIndicatorColor) {
    dropTargetBorder = Self.border(from: focusColor)
    let opacity: CGFloat = options.increasesContrast ? 0.75 : 0.6
    quietText = NSColor(name: nil) { appearance in
      var label = NSColor.labelColor
      appearance.performAsCurrentDrawingAppearance {
        label = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
      }
      return label.withAlphaComponent(opacity)
    }
  }

  /// `color`, opaque, moved toward black in light appearances and toward white in dark ones until
  /// it stands out at 3 : 1 from the window and from a filled field on it, whatever accent color
  /// the user chose.
  private static func border(from color: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      let window = NSColor.windowBackgroundColor.resolved(in: appearance)
      let surfaces = [window, NSColor.quaternarySystemFill.resolved(in: appearance).over(window)]
      let base = color.resolved(in: appearance).withAlphaComponent(1)
      let toward: NSColor = window.luminance < 0.5 ? .white : .black
      for step in 0...Self.borderSteps {
        let fraction = CGFloat(step) / CGFloat(Self.borderSteps)
        let border = base.blended(withFraction: fraction, of: toward) ?? base
        if surfaces.allSatisfy({ border.contrastRatio(with: $0) >= Self.borderContrast }) {
          return border
        }
      }
      return toward
    }
  }

  /// The least contrast of a border that says something.
  private static let borderContrast: CGFloat = 3

  /// The number of steps from the focus color to black or white, each a twentieth of the way.
  private static let borderSteps = 20
}
