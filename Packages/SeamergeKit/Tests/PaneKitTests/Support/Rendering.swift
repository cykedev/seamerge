import AppKit
import Testing

/// An appearance together with the contrast setting of the system, which the app passes to the
/// theme rather than leaving it to the appearance.
///
/// An appearance with increased contrast cannot be made by name: `NSAppearance(named:)` gives
/// the plain one. So system colors look the same with and without the setting here; the colors
/// of the theme take their values for increased contrast.
struct Look: Sendable, CustomTestStringConvertible {
  var appearanceName: NSAppearance.Name
  var increasesContrast: Bool

  /// The four looks that every color is checked and pictured in.
  static let all = [
    Look(appearanceName: .aqua, increasesContrast: false),
    Look(appearanceName: .darkAqua, increasesContrast: false),
    Look(appearanceName: .aqua, increasesContrast: true),
    Look(appearanceName: .darkAqua, increasesContrast: true),
  ]

  /// A short name for file names and test results.
  var name: String {
    (appearanceName == .darkAqua ? "dark" : "light")
      + (increasesContrast ? "-increased-contrast" : "")
  }

  var testDescription: String { name }

  /// The appearance to draw in.
  @MainActor var appearance: NSAppearance {
    guard let appearance = NSAppearance(named: appearanceName) else {
      preconditionFailure("The system has no appearance named \(appearanceName.rawValue)")
    }
    return appearance
  }
}

/// Draws views without a screen, the way the pictures for review are made.
@MainActor
enum Rendering {
  /// Puts `view` into a window that is never shown, at `size`, so that it lays out and draws as
  /// it would on screen.
  ///
  /// With `isKey`, the window acts as the key window, which a window without a screen never
  /// becomes, so that a focused selection shows in the accent color. The window draws in the
  /// light appearance unless `appearance` says otherwise, whatever the system shows.
  static func host(
    _ view: NSView, size: CGSize, appearance: NSAppearance? = NSAppearance(named: .aqua),
    isKey: Bool = false
  ) -> NSWindow {
    let window = (isKey ? KeyWindow.self : NSWindow.self).init(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    // Without a screen, the window would blend in a linear color space, which makes every
    // translucent fill lighter than on a display.
    window.colorSpace = .sRGB
    window.appearance = appearance
    window.contentView = view
    view.frame = CGRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    return window
  }

  /// Draws `view` into a bitmap at the backing scale of the screen.
  static func bitmap(of view: NSView) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
  }

  /// The color of the bitmap at a point given in the view's coordinates, top left as origin.
  ///
  /// The window draws in sRGB, so the components are sRGB, although `colorAt` labels them as
  /// calibrated RGB; converting them would change them.
  static func color(in bitmap: NSBitmapImageRep, at point: CGPoint) throws -> NSColor {
    try #require(bitmap.colorSpace == .sRGB, "the bitmap is in \(bitmap.colorSpace)")
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    let color = try #require(
      bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
    return NSColor(
      srgbRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
      alpha: color.alphaComponent)
  }

  /// Writes `bitmap` as a PNG named `name` into the folder for pictures and returns its URL.
  ///
  /// The folder is `SEAMERGE_PICTURES` if that is set, and a folder in the temporary directory
  /// otherwise.
  @discardableResult
  static func write(_ bitmap: NSBitmapImageRep, named name: String) throws -> URL {
    let folder =
      ProcessInfo.processInfo.environment["SEAMERGE_PICTURES"].map { URL(filePath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "SeamergePictures/PaneKit")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "\(name).png")
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
    return url
  }
}

extension Rendering {
  /// Writes `text` as a text file named `name` into the folder for pictures, next to them.
  static func writeText(_ text: String, named name: String) throws {
    let folder =
      ProcessInfo.processInfo.environment["SEAMERGE_PICTURES"].map { URL(filePath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "SeamergePictures/PaneKit")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data((text + "\n").utf8).write(to: folder.appending(path: "\(name).txt"))
  }
}

/// A window that acts as the key window without being shown, until a test makes it give that up.
final class KeyWindow: NSWindow {
  var actsAsKey = true

  override var isKeyWindow: Bool { actsAsKey }
}
