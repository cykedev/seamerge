import AppKit
import Testing

@testable import SeamergeUI

/// Draws the window Settings for the visual review, in every look.
@MainActor
@Suite(.serialized) struct SettingsPicturesTests {
  @Test(arguments: Look.all)
  func settingsArePictured(look: Look) throws {
    let controller = SettingsWindowController(settings: .private())
    let window = try #require(controller.window)
    defer { window.close() }
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(Rendering.bitmap(of: window), named: "settings-\(look.name)")
  }
}
