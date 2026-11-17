import AppKit

/// Symbols as images of a size, weight and color, each made once.
///
/// AppKit draws a view again each time it moves, so a view that scrolls with the text draws on
/// every step; a symbol made anew each time would be looked up and rendered anew as well. An
/// image is kept by its color as the appearance that draws resolves it: the colors of a theme are
/// made anew each time they are asked for, and a change of the appearance or its contrast asks
/// for images of other colors.
@MainActor
final class SymbolImages {
  private struct Key: Hashable {
    var name: String
    var pointSize: CGFloat
    var weight: NSFont.Weight
    var scale: NSImage.SymbolScale?
    var color: NSColor
  }

  private var images: [Key: NSImage] = [:]

  /// How many images have been made so far, counting those made again after ``removeAll()``.
  private(set) var madeCount = 0

  /// The symbol `name` at `pointSize` in `weight` and `color`, at `scale` or, for `nil`, at the
  /// scale of the configuration without one; `nil` if the system has no such symbol.
  ///
  /// `color` is resolved in the current drawing appearance, that of the view that draws.
  func image(
    named name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium,
    scale: NSImage.SymbolScale? = nil, color: NSColor
  ) -> NSImage? {
    let resolved = color.usingColorSpace(.sRGB) ?? color
    let key = Key(
      name: name, pointSize: pointSize, weight: weight, scale: scale, color: resolved)
    if let image = images[key] {
      return image
    }
    let size =
      if let scale {
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: scale)
      } else {
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
      }
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        size.applying(NSImage.SymbolConfiguration(paletteColors: [resolved])))
    images[key] = image
    madeCount += 1
    return image
  }

  /// Forgets the images, after the colors or sizes they are asked for changed for good.
  func removeAll() {
    images.removeAll()
  }
}
