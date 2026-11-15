import AppKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the window Compare Files for the visual review: empty, with two and
/// with three files, with recent comparisons, as the service leaves it, in every look; and checks
/// the contrast of what the fields draw.
@MainActor
@Suite(.serialized) struct CompareFilesPicturesTests {
  /// What the fields hold in a picture.
  enum Filling: String, CaseIterable, CustomTestStringConvertible {
    case empty
    case twoFiles = "two-files"
    case threeFiles = "three-files"

    var testDescription: String { rawValue }

    var files: [URL] {
      let folder = URL(filePath: NSHomeDirectory()).appending(path: "Projects/app")
      return switch self {
      case .empty: []
      case .twoFiles:
        [folder.appending(path: "LoginView.swift"), folder.appending(path: "LoginView copy.swift")]
      case .threeFiles:
        [
          folder.appending(path: "Theme.json"), folder.appending(path: "Theme base.json"),
          folder.appending(path: "Theme mine.json"),
        ]
      }
    }
  }

  @Test(arguments: Filling.allCases, Look.all)
  func windowIsPictured(filling: Filling, look: Look) throws {
    let fixture = try CompareFilesFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    if filling != .empty {
      #expect(fixture.controller.fill(with: filling.files))
    }
    try picture(fixture, look: look, named: "compare-files-\(filling.rawValue)-\(look.name)")
  }

  /// The window draws nothing translucent and marks nothing with color alone, so these look as
  /// the plain pictures do; they are drawn to show that.
  @Test(arguments: [
    ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
    ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
  ])
  func windowIsPicturedWithTheOtherSettings(setting: (name: String, options: DisplayOptions))
    throws
  {
    let fixture = try CompareFilesFixture(displayOptions: setting.options)
    #expect(fixture.controller.fill(with: Array(Filling.twoFiles.files.prefix(1))))
    fixture.controller.dropTargets = [.right: "Drop to Use as Right"]
    try picture(fixture, look: .light, named: "compare-files-\(setting.name)-light")
  }

  @Test(arguments: [Look.light, .dark])
  func windowWithRecentComparisonsIsPictured(look: Look) throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    fixture.recentComparisons.add(
      FileComparison(left: try files.file("Theme.json"), right: try files.file("Theme old.json")))
    fixture.recentComparisons.add(
      FileComparison(
        left: try files.file("Package.swift"), base: try files.file("Package base.swift"),
        right: try files.file("Package mine.swift")))
    fixture.recentComparisons.add(
      FileComparison(
        left: try files.file("LoginView.swift"), right: try files.file("LoginView copy.swift")))
    #expect(fixture.controller.fill(with: Array(Filling.twoFiles.files.prefix(1))))
    try picture(fixture, look: look, named: "compare-files-recent-\(look.name)")
  }

  /// What the service Compare with Seamerge leaves in the window: one file to compare with the
  /// next, or the sentence about a selection it does not compare.
  @Test(arguments: Look.all)
  func selectionsOfTheServiceArePictured(look: Look) throws {
    let fixture = try CompareFilesFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    defer { fixture.window.close() }
    fixture.controller.compare(with: Filling.twoFiles.files[0])
    try picture(fixture, look: look, named: "compare-files-service-one-\(look.name)")

    fixture.controller.showUnsupportedSelection()
    try picture(fixture, look: look, named: "compare-files-service-unsupported-\(look.name)")
  }

  @Test func longNamesAreShortenedInTheMiddle() throws {
    let fixture = try CompareFilesFixture()
    let folder = URL(filePath: NSHomeDirectory()).appending(
      path: "Projects/a-project-with-a-long-name/Sources/Features/Authentication/Views")
    let files = [
      "LoginViewControllerWithTwoFactorAuthenticationAndRecovery.swift",
      "LoginViewControllerWithTwoFactorAuthenticationAndRecovery copy.swift",
    ].map { folder.appending(path: $0) }
    #expect(fixture.controller.fill(with: files))

    try picture(fixture, look: .light, named: "compare-files-long-names-light")
    let labels = try fixture.field(.left).subviews.compactMap { $0 as? NSStackView }
      .flatMap(\.arrangedSubviews).compactMap { $0 as? NSTextField }
    let name = try #require(labels.first { $0.stringValue == files[0].lastPathComponent })
    #expect(name.lineBreakMode == .byTruncatingMiddle)
    #expect(name.frame.width <= CompareFilesMetrics.fieldSize.width)
  }

  @Test(arguments: [Look.light, .dark])
  func dropTargetIsPicturedWithItsWords(look: Look) throws {
    let files = try SampleFiles()
    let fixture = try CompareFilesFixture()
    #expect(fixture.controller.fill(with: [try files.file("LoginView.swift")]))
    let drag = DragInTest(files: [
      try files.file("base.swift"), try files.file("theirs.swift"), try files.file("mine.swift"),
    ])

    #expect(fixture.controller.operation(forDrag: drag, onto: nil) == .copy)

    #expect(fixture.captions == ["Drop to Use as A", "Drop to Use as Base", "Drop to Use as B"])
    try picture(fixture, look: look, named: "compare-files-drop-target-\(look.name)")
    fixture.controller.dragDidEnd()
    #expect(fixture.captions == ["Left", "Base (Optional)", "Right"])
  }

  /// The border of an empty field and that of a drop target stand out from the window and from
  /// a filled field on it.
  ///
  /// The drop target starts from the focus color of the system, which follows the accent color
  /// the user chose; it is measured with each of the accent colors of macOS as the focus color,
  /// so that the test does not depend on the setting of the Mac it runs on.
  @Test(arguments: Look.all)
  func bordersStandOutFromTheWindowWhateverTheAccentColor(look: Look) throws {
    let colors = CompareFilesColors(DisplayOptions(increasesContrast: look.increasesContrast))
    let window = try #require(Contrast.resolve(.windowBackgroundColor, in: look.appearance))
    let field = Contrast.over(Contrast.resolve(colors.filledFieldFill, in: look.appearance), window)
    let accents: [NSColor] = [
      .systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange, .systemYellow,
      .systemGreen, .systemGray,
    ]
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    let borders =
      [colors.emptyFieldBorder]
      + accents.map { CompareFilesColors(options, focusColor: $0).dropTargetBorder }
    for (index, border) in borders.enumerated() {
      let resolved = Contrast.resolve(border, in: look.appearance)
      for background in [window, field] {
        let ratio = Contrast.ratio(Contrast.over(resolved, background), background)
        #expect(ratio >= 3, "border \(index): \(String(format: "%.2f", ratio))")
      }
    }
  }

  /// A focus color that stands out already keeps its hue and value.
  @Test func dropTargetKeepsAFocusColorThatStandsOut() throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let dark = NSColor(srgbRed: 0, green: 0.2, blue: 0.6, alpha: 1)
    let resolved = try #require(
      Contrast.resolve(
        CompareFilesColors(DisplayOptions(), focusColor: dark).dropTargetBorder, in: appearance
      )?.usingColorSpace(.sRGB))
    let components = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
    for (component, expected) in zip(components, [0, 0.2, 0.6]) {
      #expect(abs(component - expected) < 0.001)
    }
  }

  @Test(arguments: Look.all)
  func quietTextIsLegibleOnTheWindowAndOnAFilledField(look: Look) throws {
    let colors = CompareFilesColors(DisplayOptions(increasesContrast: look.increasesContrast))
    let window = try #require(Contrast.resolve(.windowBackgroundColor, in: look.appearance))
    let field = Contrast.over(Contrast.resolve(colors.filledFieldFill, in: look.appearance), window)
    let text = Contrast.resolve(colors.quietText, in: look.appearance)

    for background in [window, field] {
      let ratio = Contrast.ratio(Contrast.over(text, background), background)
      #expect(ratio >= 4.5, "\(ratio)")
    }
  }

  private func picture(_ fixture: CompareFilesFixture, look: Look, named name: String) throws {
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
