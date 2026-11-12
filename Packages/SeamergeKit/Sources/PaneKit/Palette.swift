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
}
