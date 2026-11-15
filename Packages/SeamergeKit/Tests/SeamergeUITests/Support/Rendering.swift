import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// An appearance together with the contrast setting of the system, which the window passes to
/// the theme rather than leaving it to the appearance.
///
/// An appearance with increased contrast cannot be made by name: `NSAppearance(named:)` gives
/// the plain one. So system colors look the same with and without the setting here; the colors
/// of the theme take their values for increased contrast.
struct Look: Sendable, CustomTestStringConvertible {
  var appearanceName: NSAppearance.Name
  var increasesContrast: Bool

  static let light = Look(appearanceName: .aqua, increasesContrast: false)
  static let dark = Look(appearanceName: .darkAqua, increasesContrast: false)

  /// The four looks that every view is pictured in.
  static let all = [
    light, dark,
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

/// Draws windows without a screen, the way the pictures for review are made.
@MainActor
enum Rendering {
  /// Prepares `window` to draw as on a display, at `size`, in `appearance`.
  static func prepare(_ window: NSWindow, size: CGSize, appearance: NSAppearance) {
    // Without a screen, the window would blend in a linear color space, which makes every
    // translucent fill lighter than on a display.
    window.colorSpace = .sRGB
    window.appearance = appearance
    window.setContentSize(size)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  /// Draws the whole window, title bar included, into a bitmap at the backing scale.
  static func bitmap(of window: NSWindow) throws -> NSBitmapImageRep {
    let frameView = try #require(window.contentView?.superview)
    frameView.layoutSubtreeIfNeeded()
    let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    try drawGlassContents(of: frameView, into: bitmap)
    return bitmap
  }

  /// Draws the sidebar over the bitmap of the window: caching the display skips the glass of the
  /// sidebar with all it holds, while its rows and its bottom line draw on their own; so the
  /// picture shows them on the window background, with a plain selection, instead of the glass.
  private static func drawGlassContents(
    of frameView: NSView, into bitmap: NSBitmapImageRep
  ) throws {
    let sidebars = descendants(of: frameView).compactMap { $0 as? NSGlassEffectView }.filter {
      glass in
      !glass.isHiddenOrHasHiddenAncestor && descendants(of: glass).contains { $0 is NSTableView }
    }
    guard !sidebars.isEmpty else { return }
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let appearance = frameView.window?.appearance ?? NSAppearance.currentDrawing()
    var background = NSColor.windowBackgroundColor.cgColor
    var selection = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
    appearance.performAsCurrentDrawingAppearance {
      background = NSColor.windowBackgroundColor.cgColor
      selection = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
    }
    for sidebar in sidebars {
      let frame = sidebar.convert(sidebar.bounds, to: frameView)
      context.cgContext.setFillColor(background)
      context.cgContext.fill(frame)
      // The buttons of the title bar above the sidebar.
      let buttons = descendants(of: frameView).filter { view in
        view is NSButton && !view.isHiddenOrHasHiddenAncestor && !view.isDescendant(of: sidebar)
          && view.convert(view.bounds, to: frameView).intersects(frame)
      }
      let inside = descendants(of: sidebar)
      for case let row as NSTableRowView in inside where row.isSelected {
        let rowFrame = row.convert(row.bounds, to: frameView).insetBy(dx: 10, dy: 0)
        context.cgContext.setFillColor(selection)
        context.cgContext.addPath(
          CGPath(roundedRect: rowFrame, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.cgContext.fillPath()
      }
      // Rows, lines and fields; each drawn once, with whatever lies inside it.
      let isPart = { (view: NSView) in
        view is NSTableCellView || view is NSStackView || view is NSTextField
      }
      let parts = inside.filter(isPart).filter { part in
        !inside.contains { $0 !== part && isPart($0) && part.isDescendant(of: $0) }
      }
      for part in buttons + parts where !part.isHiddenOrHasHiddenAncestor {
        let visible = part.visibleRect
        guard !visible.isEmpty,
          let partBitmap = part.bitmapImageRepForCachingDisplay(in: visible)
        else { continue }
        part.cacheDisplay(in: visible, to: partBitmap)
        partBitmap.draw(
          in: part.convert(visible, to: frameView), from: .zero, operation: .sourceOver,
          fraction: 1, respectFlipped: true, hints: nil)
      }
    }
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
  }

  /// Writes `bitmap` as a PNG named `name` into the folder for pictures and returns its URL.
  ///
  /// The folder is `SEAMERGE_PICTURES` if that is set, and a folder in the temporary directory
  /// otherwise.
  @discardableResult
  static func write(_ bitmap: NSBitmapImageRep, named name: String) throws -> URL {
    let url = try folder().appending(path: "\(name).png")
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
    return url
  }

  /// Writes `text` into a file named `name` with the extension `txt` next to the pictures, for
  /// what has no picture without a screen, such as a menu.
  static func write(text: String, named name: String) throws {
    try Data((text + "\n").utf8).write(to: try folder().appending(path: "\(name).txt"))
  }

  private static func folder() throws -> URL {
    let folder =
      ProcessInfo.processInfo.environment["SEAMERGE_PICTURES"].map { URL(filePath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "SeamergePictures/SeamergeUI")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
