import AppKit

/// The four appearances that the palette gives values of their own.
enum PaletteAppearance: Sendable, CaseIterable {
  case light
  case dark
  case lightHighContrast
  case darkHighContrast

  /// The palette appearance that comes closest to `appearance`, with increased contrast if the
  /// appearance has it or if `increasesContrast` asks for it.
  init(_ appearance: NSAppearance, increasesContrast: Bool) {
    let match = appearance.bestMatch(from: [
      .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ])
    switch match {
    case .darkAqua: self = .dark
    case .accessibilityHighContrastAqua: self = .lightHighContrast
    case .accessibilityHighContrastDarkAqua: self = .darkHighContrast
    default: self = .light
    }
    if increasesContrast {
      self = self == .dark ? .darkHighContrast : self == .light ? .lightHighContrast : self
    }
  }
}

/// One value for each of the four palette appearances.
struct AppearanceValues<Value: Sendable>: Sendable {
  var light: Value
  var dark: Value
  var lightHighContrast: Value
  var darkHighContrast: Value

  subscript(appearance: PaletteAppearance) -> Value {
    switch appearance {
    case .light: light
    case .dark: dark
    case .lightHighContrast: lightHighContrast
    case .darkHighContrast: darkHighContrast
    }
  }
}

/// The fixed values that every color of the panes is derived from.
///
/// Neutral colors are never fixed values: they come from the dynamic system colors, so that they
/// follow the appearance and the accessibility settings of the system.
enum Palette {
  /// The surface value of each role, as 0xRRGGBB in sRGB.
  ///
  /// Dark surfaces keep their value with increased contrast: a brighter tint behind light text
  /// would lower the contrast that the setting asks to raise. Only the symbols get brighter.
  static func surface(of role: ColorRole) -> AppearanceValues<UInt32> {
    AppearanceValues(
      light: lightSurface(of: role), dark: darkSurface(of: role),
      lightHighContrast: lightSurface(of: role), darkHighContrast: darkSurface(of: role))
  }

  /// The symbol value of each role, as 0xRRGGBB in sRGB.
  ///
  /// In light appearances the symbol value is darker than the surface value where the surface
  /// value would be too weak on its own tint; in dark appearances one value serves both.
  static func symbol(of role: ColorRole) -> AppearanceValues<UInt32> {
    switch role {
    case .a:
      AppearanceValues(
        light: 0x1464D2, dark: 0x5AA6FF, lightHighContrast: 0x104EA4, darkHighContrast: 0x8CC2FF)
    case .base:
      AppearanceValues(
        light: 0x8F7200, dark: 0xEBCB3A, lightHighContrast: 0x6F5900, darkHighContrast: 0xFFE066)
    case .b:
      AppearanceValues(
        light: 0x098159, dark: 0x2FC7A1, lightHighContrast: 0x076143, darkHighContrast: 0x6FE0C2)
    case .conflict:
      AppearanceValues(
        light: 0xC2261C, dark: 0xFF5A52, lightHighContrast: 0x971E16, darkHighContrast: 0xFF8A84)
    }
  }

  private static func lightSurface(of role: ColorRole) -> UInt32 {
    switch role {
    case .a: 0x1464D2
    case .base: 0xB38F00
    case .b: 0x0A8F63
    case .conflict: 0xC2261C
    }
  }

  /// The dark surface value of each role: the symbol value, except for the base, whose yellow
  /// turns olive at low opacity on a dark gray and is therefore warmer.
  private static func darkSurface(of role: ColorRole) -> UInt32 {
    role == .base ? 0xF5B841 : symbol(of: role).dark
  }

  /// The opacity of a role's surface value behind the rows of a block.
  static let rowOpacity = AppearanceValues<CGFloat>(
    light: 0.18, dark: 0.24, lightHighContrast: 0.24, darkHighContrast: 0.26)

  /// The opacity that a changed run within a line adds up to, row tint included.
  static let runOpacity = AppearanceValues<CGFloat>(
    light: 0.36, dark: 0.40, lightHighContrast: 0.44, darkHighContrast: 0.42)

  /// The strength of the base tint, relative to the row tint: full in light appearances, quieter
  /// in dark ones, where even a warm yellow stands out more than the blue and green of the sides.
  static let baseStrength = AppearanceValues<CGFloat>(
    light: 1, dark: 0.75, lightHighContrast: 1, darkHighContrast: 0.85)

  /// The strength of the base tint while a conflict is open, relative to the row tint: full in
  /// light appearances, quieter in dark ones, where red on dark gray stands out far more.
  static let openConflictStrength = AppearanceValues<CGFloat>(
    light: 1, dark: 0.6, lightHighContrast: 1, darkHighContrast: 0.7)

  /// The opacity of the label color behind text typed by hand into the result.
  static let handwrittenOpacity = AppearanceValues<CGFloat>(
    light: 0.08, dark: 0.12, lightHighContrast: 0.11, darkHighContrast: 0.16)

  /// The opacity of the label color behind the rows of the current block on a pane that the
  /// block leaves untinted, before the factor of the current block.
  static let quietOpacity = AppearanceValues<CGFloat>(
    light: 0.04, dark: 0.06, lightHighContrast: 0.06, darkHighContrast: 0.08)

  /// The opacity of the selection, which lies above the row fills.
  static let selectionOpacity = AppearanceValues<CGFloat>(
    light: 0.45, dark: 0.55, lightHighContrast: 0.55, darkHighContrast: 0.65)

  /// How much stronger than the rows of its block the hairline at an edge of the block is
  /// tinted: strong enough to stand out against the rows of the current block too.
  static let edgeFactor = AppearanceValues<CGFloat>(
    light: 3.2, dark: 3.0, lightHighContrast: 3.2, darkHighContrast: 3.0)

  /// The opacity of the label color for the hairline that alone separates two neutral blocks,
  /// such as two parts typed by hand: as strong as a sign on the gray of the current block.
  static let neutralBoundaryOpacity = AppearanceValues<CGFloat>(
    light: 0.6, dark: 0.6, lightHighContrast: 0.75, darkHighContrast: 0.75)

  /// How much stronger the rows of the current block are tinted.
  static let currentBlockFactor: CGFloat = 1.5

  /// How much weaker filler rows are tinted than the rows of their block.
  static let fillerFactor: CGFloat = 0.5

  /// The opacity of the label color for the line numbers.
  static let lineNumberOpacity = AppearanceValues<CGFloat>(
    light: 0.66, dark: 0.66, lightHighContrast: 0.80, darkHighContrast: 0.80)

  /// The opacity of the label color for the invisible characters.
  static let invisibleCharacterOpacity = AppearanceValues<CGFloat>(
    light: 0.46, dark: 0.53, lightHighContrast: 0.60, darkHighContrast: 0.60)

  /// The opacity of the label color behind the marks of the overview bar.
  static let overviewBackgroundOpacity = AppearanceValues<CGFloat>(
    light: 0.03, dark: 0.04, lightHighContrast: 0.05, darkHighContrast: 0.06)

  /// The opacity of the label color in the area of the overview bar that shows the visible part.
  static let visibleRegionOpacity = AppearanceValues<CGFloat>(
    light: 0.10, dark: 0.14, lightHighContrast: 0.12, darkHighContrast: 0.18)

  /// The opacity of the label color for the outline of the visible area in the overview bar.
  static let visibleRegionOutlineOpacity = AppearanceValues<CGFloat>(
    light: 0.18, dark: 0.22, lightHighContrast: 0.50, darkHighContrast: 0.55)

  /// The opacity of the label color behind the bar of a collapsed run.
  static let collapsedRunOpacity = AppearanceValues<CGFloat>(
    light: 0.05, dark: 0.07, lightHighContrast: 0.08, darkHighContrast: 0.10)

  /// The opacity of the label color behind the bar of a collapsed run while it is pressed.
  static let pressedCollapsedRunOpacity = AppearanceValues<CGFloat>(
    light: 0.12, dark: 0.16, lightHighContrast: 0.16, darkHighContrast: 0.20)

  /// The opacity of the label color for the ellipsis and the label on the bar of a collapsed run.
  static let collapsedRunTextOpacity = AppearanceValues<CGFloat>(
    light: 0.66, dark: 0.66, lightHighContrast: 0.80, darkHighContrast: 0.80)

  /// The opacity of the label color for the preview of a conflict in the result.
  static let previewTextOpacity = AppearanceValues<CGFloat>(
    light: 0.60, dark: 0.80, lightHighContrast: 0.60, darkHighContrast: 0.85)
}

extension NSColor {
  /// The sRGB color of a 0xRRGGBB value.
  convenience init(rgb: UInt32, alpha: CGFloat = 1) {
    self.init(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
  }

  /// This color as it is drawn in `appearance`, converted to sRGB.
  func resolved(in appearance: NSAppearance) -> NSColor {
    var resolved = self
    appearance.performAsCurrentDrawingAppearance {
      resolved = usingColorSpace(.sRGB) ?? self
    }
    return resolved
  }

  /// This color drawn over the opaque `background`, as an opaque color in sRGB.
  func over(_ background: NSColor) -> NSColor {
    let top = usingColorSpace(.sRGB) ?? self
    let bottom = background.usingColorSpace(.sRGB) ?? background
    let alpha = top.alphaComponent
    return NSColor(
      srgbRed: top.redComponent * alpha + bottom.redComponent * (1 - alpha),
      green: top.greenComponent * alpha + bottom.greenComponent * (1 - alpha),
      blue: top.blueComponent * alpha + bottom.blueComponent * (1 - alpha), alpha: 1)
  }

  /// The relative luminance of this color in sRGB, from 0 for black to 1 for white.
  var luminance: CGFloat {
    let color = usingColorSpace(.sRGB) ?? self
    func linear(_ component: CGFloat) -> CGFloat {
      component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
      + 0.0722 * linear(color.blueComponent)
  }
}
