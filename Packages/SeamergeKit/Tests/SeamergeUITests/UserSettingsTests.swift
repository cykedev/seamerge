import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// The settings in the user defaults: every value outlasts a launch, values out of range read as
/// the standard, and what the windows remembered before is where new windows start.
@MainActor
struct UserSettingsTests {
  @Test func everySettingOutlastsALaunch() throws {
    let defaults = UserDefaults.privateSuite()
    let family = try #require(UserSettings.monospacedFamilies.first, "a font of fixed width")
    let settings = UserSettings(defaults: defaults)

    settings.fontFamily = family
    settings.fontSize = 16
    settings.lineSpacing = .compact
    settings.tabWidth = 2
    settings.comparisonMode = .exact
    settings.showsBase = false
    settings.highlightsSyntax = false
    settings.wrapsLines = true
    settings.showsInvisibles = true
    settings.goesToNextConflict = false

    let relaunched = UserSettings(defaults: defaults)
    #expect(relaunched.fontFamily == family)
    #expect(relaunched.fontSize == 16)
    #expect(relaunched.lineSpacing == .compact)
    #expect(relaunched.tabWidth == 2)
    #expect(relaunched.comparisonMode == .exact)
    #expect(!relaunched.showsBase)
    #expect(!relaunched.highlightsSyntax)
    #expect(relaunched.wrapsLines)
    #expect(relaunched.showsInvisibles)
    #expect(!relaunched.goesToNextConflict)
  }

  @Test func freshSettingsAreTheStandard() {
    let settings = UserSettings.private()
    #expect(settings.fontFamily == nil)
    #expect(settings.codeFont(ofSize: 13) == .monospacedSystemFont(ofSize: 13, weight: .regular))
    #expect(settings.fontSize == 13)
    #expect(settings.lineSpacing == .standard)
    #expect(settings.tabWidth == 4)
    #expect(settings.comparisonMode == .windowDefault)
    #expect(settings.showsBase && settings.highlightsSyntax && settings.goesToNextConflict)
    #expect(!settings.wrapsLines && !settings.showsInvisibles)
    #expect(settings.showsFooter && settings.showsFileList)
    #expect(settings.sourcesFraction == nil)
  }

  @Test func valuesOutOfRangeOrUnknownReadAsTheStandard() {
    let defaults = UserDefaults.privateSuite()
    defaults.set("No Such Font", forKey: "CodeFontFamily")
    defaults.set(99.0, forKey: "CodeFontSize")
    defaults.set("cramped", forKey: "LineSpacing")
    defaults.set(1, forKey: "TabWidth")
    defaults.set("fuzzy", forKey: "ComparisonMode")
    defaults.set(1.5, forKey: "SourcesFraction")

    let settings = UserSettings(defaults: defaults)
    #expect(settings.fontFamily == nil)
    #expect(settings.fontSize == 13)
    #expect(settings.lineSpacing == .standard)
    #expect(settings.tabWidth == 4)
    #expect(settings.comparisonMode == .windowDefault)
    #expect(settings.sourcesFraction == nil)
  }

  @Test func sizeAndTabWidthBeyondTheirRangesAreKeptAsTheNearestWithin() {
    let defaults = UserDefaults.privateSuite()
    let settings = UserSettings(defaults: defaults)

    settings.fontSize = 40
    settings.tabWidth = 0

    #expect(settings.fontSize == UserSettings.fontSizes.upperBound)
    #expect(settings.tabWidth == UserSettings.tabWidths.lowerBound)
    let relaunched = UserSettings(defaults: defaults)
    #expect(relaunched.fontSize == UserSettings.fontSizes.upperBound)
    #expect(relaunched.tabWidth == UserSettings.tabWidths.lowerBound)
  }

  @Test func whatTheWindowsRememberedIsWhereNewWindowsStart() {
    let defaults = UserDefaults.privateSuite()
    defaults.set(true, forKey: "WrapsLines")
    defaults.set(true, forKey: "HighlightsNoSyntax")
    defaults.set(true, forKey: "HidesFooter")
    defaults.set(true, forKey: "HidesFileList")

    let settings = UserSettings(defaults: defaults)
    #expect(settings.wrapsLines)
    #expect(!settings.highlightsSyntax)
    #expect(!settings.showsFooter)
    #expect(!settings.showsFileList)
  }

  @Test func chosenFamilyGivesTheCodeFontAtEverySize() throws {
    let settings = UserSettings.private()
    let family = try #require(UserSettings.monospacedFamilies.first, "a font of fixed width")
    settings.fontFamily = family
    let font = settings.codeFont(ofSize: 17)
    #expect(font.familyName == family)
    #expect(font.pointSize == 17)
    #expect(font.isFixedPitch)
  }

  @Test func listOfFamiliesOffersOnlyFontsOfFixedWidthAndTheSystemFontNotAgain() {
    let families = UserSettings.monospacedFamilies
    #expect(!families.contains("SF Mono"))
    #expect(!families.contains("Helvetica"))
    #expect(families == families.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
  }
}
