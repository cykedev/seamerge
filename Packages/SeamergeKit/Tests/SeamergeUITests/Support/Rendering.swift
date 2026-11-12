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
    return bitmap
  }

  /// Writes `bitmap` as a PNG named `name` into the folder for pictures and returns its URL.
  ///
  /// The folder is `SEAMERGE_PICTURES` if that is set, and a folder in the temporary directory
  /// otherwise.
  @discardableResult
  static func write(_ bitmap: NSBitmapImageRep, named name: String) throws -> URL {
    let folder =
      ProcessInfo.processInfo.environment["SEAMERGE_PICTURES"].map { URL(filePath: $0) }
      ?? FileManager.default.temporaryDirectory.appending(path: "SeamergePictures/SeamergeUI")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "\(name).png")
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
    return url
  }
}

extension SessionSplitViewController {
  /// The pane of `role`, if the input takes part.
  func sourcePane(_ role: Role) -> PaneView? {
    sourcePanes.first { $0.role == role }?.pane
  }
}
