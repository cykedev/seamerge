import AppKit
import Testing

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

  /// `color` as it resolves in `appearance`, in sRGB; for what a fill draws, see
  /// ``drawn(_:in:)``.
  @MainActor
  static func resolve(_ color: NSColor?, in appearance: NSAppearance) -> NSColor? {
    guard let color else { return nil }
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.sRGB)
    }
    return resolved
  }

  /// `color` as a fill in `appearance` draws it, in sRGB.
  ///
  /// It can differ from the color that `color` resolves to: in dark appearances, a fill in the
  /// window background draws lighter.
  @MainActor
  static func drawn(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    appearance.performAsCurrentDrawingAppearance {
      color.setFill()
      CGRect(x: 0, y: 0, width: 1, height: 1).fill()
    }
    return try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
  }

  private static func luminance(_ color: NSColor) -> CGFloat {
    func linear(_ component: CGFloat) -> CGFloat {
      component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
      + 0.0722 * linear(color.blueComponent)
  }
}
