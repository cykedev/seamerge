import AppKit

/// The contrast between colors as WCAG defines it, for colors as they are drawn.
enum Contrast {
  /// The contrast ratio between two opaque colors, from 1 to 21.
  static func ratio(_ first: NSColor, _ second: NSColor) -> CGFloat {
    let (lighter, darker) = (
      max(luminance(first), luminance(second)), min(luminance(first), luminance(second))
    )
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// `top` drawn over the opaque `bottom`.
  static func over(_ top: NSColor?, _ bottom: NSColor) -> NSColor {
    let bottom = bottom.usingColorSpace(.sRGB) ?? bottom
    guard let top = top?.usingColorSpace(.sRGB) else { return bottom }
    let alpha = top.alphaComponent
    return NSColor(
      srgbRed: top.redComponent * alpha + bottom.redComponent * (1 - alpha),
      green: top.greenComponent * alpha + bottom.greenComponent * (1 - alpha),
      blue: top.blueComponent * alpha + bottom.blueComponent * (1 - alpha), alpha: 1)
  }

  /// `color` as it is drawn in `appearance`, in sRGB.
  @MainActor
  static func resolve(_ color: NSColor?, in appearance: NSAppearance) -> NSColor? {
    guard let color else { return nil }
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.sRGB)
    }
    return resolved
  }

  private static func luminance(_ color: NSColor) -> CGFloat {
    func linear(_ component: CGFloat) -> CGFloat {
      component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
      + 0.0722 * linear(color.blueComponent)
  }
}
