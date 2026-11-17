import AppKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the welcome window for the visual review: with recent comparisons and
/// without, while files are dragged over it, in every look; and checks the contrast of what the
/// column with the name of the app draws on its blue.
@MainActor
@Suite(.serialized) struct WelcomePicturesTests {
  @Test(arguments: Look.all)
  func windowIsPictured(look: Look) async throws {
    let files = try SampleFiles()
    let fixture = try await fixture(look: look, options: DisplayOptions())
    try addRecentComparisons(to: fixture, in: files)
    try picture(fixture, look: look, named: "welcome-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func windowWithoutRecentComparisonsIsPictured(look: Look) async throws {
    let fixture = try await fixture(look: look, options: DisplayOptions())
    try picture(fixture, look: look, named: "welcome-empty-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func dragOverTheWindowIsPicturedWithItsWords(look: Look) async throws {
    let files = try SampleFiles()
    let fixture = try await fixture(look: look, options: DisplayOptions())
    try addRecentComparisons(to: fixture, in: files)
    let drag = DragInTest(files: [try files.file("old.swift"), try files.file("new.swift")])
    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)
    try picture(fixture, look: look, named: "welcome-drop-target-\(look.name)")
  }

  /// Without color the window looks as the plain picture does; with Reduce Transparency the
  /// column is one color instead of the gradient.
  @Test(arguments: [
    ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
    ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
  ])
  func windowIsPicturedWithTheOtherSettings(setting: (name: String, options: DisplayOptions))
    async throws
  {
    let files = try SampleFiles()
    for look in [Look.light, .dark] {
      let fixture = try await fixture(look: look, options: setting.options)
      try addRecentComparisons(to: fixture, in: files)
      try picture(fixture, look: look, named: "welcome-\(setting.name)-\(look.name)")
    }
  }

  /// The name of the app reaches 4.5 : 1 on every part of the blue, and so do the version and the
  /// words of the place to drop files; the border of the place stands out at 3 : 1, quiet and
  /// while a drop would be taken.
  @Test(arguments: [
    DisplayOptions(), DisplayOptions(increasesContrast: true),
    DisplayOptions(reducesTransparency: true),
  ])
  func textOnTheBlueIsLegible(options: DisplayOptions) throws {
    let colors = WelcomeColors(options)
    for background in colors.background {
      let fill = Contrast.over(colors.dropAreaTargetFill, background)
      let pairs: [(String, NSColor, NSColor, CGFloat)] = [
        ("name", colors.text, background, 4.5),
        ("quiet text", colors.quietText, background, 4.5),
        ("words of a drop", colors.text, fill, 4.5),
        ("border of a drop", colors.dropAreaTargetBorder, background, 3),
        ("quiet border", colors.dropAreaBorder, background, 3),
      ]
      for (name, color, surface, minimum) in pairs {
        let ratio = Contrast.ratio(Contrast.over(color, surface), surface)
        #expect(ratio >= minimum, "\(name): \(String(format: "%.2f", ratio))")
      }
    }
    #expect(
      colors.background.count
        == (options.increasesContrast || options.reducesTransparency ? 1 : 2))
  }

  private func fixture(look: Look, options: DisplayOptions) async throws -> WelcomeFixture {
    var options = options
    options.increasesContrast = options.increasesContrast || look.increasesContrast
    let (fixture, _) = try integrationFixture(.setUp, displayOptions: options)
    await fixture.controller.readIntegrationStatus()
    return fixture
  }

  private func addRecentComparisons(to fixture: WelcomeFixture, in files: borrowing SampleFiles)
    throws
  {
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("Theme.json"), right: try files.file("Theme old.json")))
    fixture.recentComparisons.add(
      FileComparison(
        left: try files.file("Package.swift"), base: try files.file("Package base.swift"),
        right: try files.file("Package mine.swift")))
    fixture.recentComparisons.add(
      FileComparison(
        folders: FolderPair(
          left: try files.subfolder("Orders 1.0"), right: try files.subfolder("Orders 1.1"))))
    fixture.recentComparisons.add(
      FileComparison(
        left: try files.file("LoginView.swift"), right: try files.file("LoginView copy.swift")))
  }

  private func picture(_ fixture: WelcomeFixture, look: Look, named name: String) throws {
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
