import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the window Keyboard Shortcuts for the visual review.
@MainActor
@Suite(.serialized) struct ShortcutOverviewPicturesTests {
  @Test(arguments: Look.all)
  func overviewIsPictured(look: Look) throws {
    for (kind, kindName) in [(Session.Kind.merge, "merge"), (.diff, "diff")] {
      let controller = ShortcutOverviewWindowController(kind: kind)
      let window = try #require(controller.window)
      defer { window.close() }
      window.colorSpace = .sRGB
      window.appearance = look.appearance
      window.contentView?.layoutSubtreeIfNeeded()
      try Rendering.write(
        Rendering.bitmap(of: window), named: "shortcuts-\(kindName)-\(look.name)")
    }
  }
}
