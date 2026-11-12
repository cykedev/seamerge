import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The letters of the badges in the headers stay legible on the badge in every look.
@MainActor
@Suite struct HeaderContrastTests {
  @Test(arguments: Look.all)
  func letterOfEveryBadgeIsLegibleOnItsBadge(look: Look) throws {
    let theme = DisplayOptions(increasesContrast: look.increasesContrast).theme
    for role in Role.allCases {
      let badge = try #require(
        Contrast.resolve(theme.symbolColor(for: role.colorRole), in: look.appearance))
      let letter = Contrast.over(
        Contrast.resolve(theme.filledLabelColor, in: look.appearance), badge)
      let ratio = Contrast.ratio(letter, badge)
      // The letter is small text: at least 4.5 : 1.
      #expect(ratio >= 4.5, "\(role) in \(look.name): \(ratio)")
    }
  }
}
