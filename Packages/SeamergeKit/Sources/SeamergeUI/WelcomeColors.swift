import AppKit

/// The colors of the column of the welcome window that carries the name of the app: the deep
/// blue of the website in both appearances, with light text on it.
///
/// The blue runs as a gradient from the top to the bottom, as on the website; with Reduce
/// Transparency or Increase Contrast it is one color, the darker one. The text is white, and
/// quieter text white with an opacity that still reaches 4.5 : 1 on the lighter end of the
/// gradient.
struct WelcomeColors {
  /// The color at the top of the gradient, and the whole column when it is one color.
  static let deepBlue = NSColor(srgbRed: 0x0A / 255, green: 0x17 / 255, blue: 0x33 / 255, alpha: 1)

  /// The color at the bottom of the gradient.
  static let waveBlue = NSColor(srgbRed: 0x14 / 255, green: 0x38 / 255, blue: 0x5F / 255, alpha: 1)

  /// The angle of the gradient in the coordinates of AppKit: from the top a little to the left
  /// down to the bottom a little to the right, as `linear-gradient(160deg, …)` on the website.
  static let gradientAngle: CGFloat = -70

  /// The colors of the background, from the start of the gradient to its end; one color when
  /// the column is drawn without a gradient.
  let background: [NSColor]

  /// The color of the name of the app and of the titles of the buttons.
  let text = NSColor.white

  /// The color of quieter text: the version and the words of the place to drop files.
  let quietText: NSColor

  /// The border of the place to drop files while nothing is dragged over the window, which still
  /// stands out at 3 : 1 on the lighter end of the gradient.
  let dropAreaBorder: NSColor

  /// The border of the place to drop files while a drag over the window would be taken.
  let dropAreaTargetBorder = NSColor.white

  /// The fill of the place to drop files while a drag over the window would be taken.
  let dropAreaTargetFill = NSColor.white.withAlphaComponent(0.14)

  /// The colors with `options`: one color instead of the gradient, and stronger quiet text,
  /// when the system reduces transparency or increases contrast.
  init(_ options: DisplayOptions) {
    let isPlain = options.reducesTransparency || options.increasesContrast
    background = isPlain ? [Self.deepBlue] : [Self.deepBlue, Self.waveBlue]
    quietText = NSColor.white.withAlphaComponent(options.increasesContrast ? 0.85 : 0.72)
    dropAreaBorder = NSColor.white.withAlphaComponent(options.increasesContrast ? 0.6 : 0.42)
  }
}
