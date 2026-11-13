import AppKit
import MergeModel
import PaneKit
import SwiftUI
import Testing

@testable import SeamergeUI

/// The badges in the headers: each in the color of a chosen toggle of its side, the base in a
/// clear yellow, with a letter that stays legible in every look.
@MainActor
@Suite struct HeaderContrastTests {
  @Test(arguments: Look.all)
  func letterOfEveryBadgeIsLegibleOnItsBadge(look: Look) throws {
    let theme = DisplayOptions(increasesContrast: look.increasesContrast).theme
    for role in Role.allCases {
      let badge = try #require(
        Contrast.resolve(theme.chosenFill(for: role.colorRole), in: look.appearance))
      let letter = Contrast.over(
        Contrast.resolve(theme.chosenSignColor(for: role.colorRole), in: look.appearance), badge)
      let ratio = Contrast.ratio(letter, badge)
      // The letter is small text: at least 4.5 : 1.
      #expect(ratio >= 4.5, "\(role) in \(look.name): \(ratio)")
    }
  }

  @Test(arguments: Look.all)
  func badgeOfTheBaseHasTheColorOfAChosenBaseToggle(look: Look) throws {
    let theme = DisplayOptions(increasesContrast: look.increasesContrast).theme
    let host = NSHostingView(rootView: SideBadge(role: .base, theme: theme))
    host.appearance = look.appearance
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
    // Within the round left end of the badge, above the letters.
    let point = CGPoint(x: WindowMetrics.badgeHeight / 2, y: 1.5)
    let sample = try #require(
      bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB))
    let expected = try #require(
      Contrast.resolve(theme.chosenFill(for: .base), in: look.appearance))
    #expect(Self.isClose(sample, expected), "\(look.name): \(sample) instead of \(expected)")
  }

  private static func isClose(_ first: NSColor, _ second: NSColor) -> Bool {
    abs(first.redComponent - second.redComponent) < 0.03
      && abs(first.greenComponent - second.greenComponent) < 0.03
      && abs(first.blueComponent - second.blueComponent) < 0.03
  }
}
