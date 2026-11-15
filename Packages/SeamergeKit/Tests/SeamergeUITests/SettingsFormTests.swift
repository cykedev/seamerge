import AppKit
import Testing

@testable import SeamergeUI

/// The menus of size and tab width in the window Settings: what they offer, what they select,
/// and that a choice there is kept.
///
/// SwiftUI draws its controls without AppKit views and builds their accessibility only for a
/// client, so the tests drive the selections the menus are bound to; the pictures of the window
/// show that both are menus like font and line spacing.
@MainActor
struct SettingsFormTests {
  @Test func menusOfferEverySizeAndTabWidthByItsName() {
    #expect(SettingsView.fontSizes.map(SettingsView.sizeText) == (9...24).map { "\($0) pt" })
    #expect(SettingsView.tabWidths.map(SettingsView.tabWidthText) == (2...8).map { "\($0) spaces" })
  }

  @Test func sizeAndTabWidthChosenInTheMenusAreKept() {
    let defaults = UserDefaults.privateSuite()
    let view = SettingsView(settings: UserSettings(defaults: defaults), fontFamilies: [])
    #expect(view.fontSizeSelection.wrappedValue == 13)
    #expect(view.tabWidthSelection.wrappedValue == 4)

    view.fontSizeSelection.wrappedValue = 16
    view.tabWidthSelection.wrappedValue = 2

    #expect(view.settings.fontSize == 16)
    #expect(view.settings.tabWidth == 2)
    let relaunched = UserSettings(defaults: defaults)
    #expect(relaunched.fontSize == 16)
    #expect(relaunched.tabWidth == 2)
  }

  @Test func sizeBetweenTwoInTheMenuSelectsTheNearest() {
    let defaults = UserDefaults.privateSuite()
    defaults.set(13.6, forKey: "CodeFontSize")
    let view = SettingsView(settings: UserSettings(defaults: defaults), fontFamilies: [])

    #expect(view.fontSizeSelection.wrappedValue == 14)
  }

  @Test func widthOfOneSpaceIsNamedInTheSingular() {
    #expect(SettingsView.tabWidthText(1) == "1 space")
    #expect(SettingsView.tabWidthText(4) == "4 spaces")
  }
}
