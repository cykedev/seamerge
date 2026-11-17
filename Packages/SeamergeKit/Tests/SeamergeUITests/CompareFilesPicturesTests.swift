import AppKit
import Testing

@testable import SeamergeUI

/// Draws the pictures of the sheets Compare Files and Merge Files for the visual review: empty,
/// filled, as the service leaves them, in every look, each on the welcome window it hangs on;
/// and checks the contrast of what the fields draw.
@MainActor
@Suite(.serialized) struct CompareFilesPicturesTests {
  /// What the sheet is for and what its fields hold in a picture.
  enum Filling: String, CaseIterable, CustomTestStringConvertible {
    case compareEmpty = "compare-empty"
    case compareFilled = "compare-two-files"
    case mergeEmpty = "merge-empty"
    case mergeFilled = "merge-three-files"

    var testDescription: String { rawValue }

    var purpose: CompareFilesWindowController.Purpose {
      switch self {
      case .compareEmpty, .compareFilled: .compare
      case .mergeEmpty, .mergeFilled: .merge
      }
    }

    var files: [URL] {
      let folder = URL(filePath: NSHomeDirectory()).appending(path: "Projects/app")
      return switch self {
      case .compareEmpty, .mergeEmpty: []
      case .compareFilled:
        [folder.appending(path: "LoginView.swift"), folder.appending(path: "LoginView copy.swift")]
      case .mergeFilled:
        [
          folder.appending(path: "Theme.json"), folder.appending(path: "Theme base.json"),
          folder.appending(path: "Theme mine.json"),
        ]
      }
    }
  }

  @Test(arguments: Filling.allCases, Look.all)
  func sheetIsPictured(filling: Filling, look: Look) throws {
    let fixture = try WelcomeFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    fixture.controller.showFilesSheet(filling.purpose)
    if filling != .compareEmpty, filling != .mergeEmpty {
      #expect(try fixture.sheet().fill(with: filling.files))
    }
    try picture(fixture, look: look, named: "sheet-\(filling.rawValue)-\(look.name)")
  }

  /// The sheets draw nothing translucent and mark nothing with color alone, so these look as the
  /// plain pictures do; they are drawn to show that.
  @Test(arguments: [
    ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
    ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
  ])
  func sheetIsPicturedWithTheOtherSettings(setting: (name: String, options: DisplayOptions))
    throws
  {
    for filling in [Filling.compareFilled, .mergeFilled] {
      let fixture = try WelcomeFixture(displayOptions: setting.options)
      fixture.controller.showFilesSheet(filling.purpose)
      let sheet = try fixture.sheet()
      #expect(sheet.fill(with: Array(filling.files.prefix(1))))
      sheet.dropTargets = [.right: "Drop to Use as \(filling == .mergeFilled ? "B" : "Right")"]
      try picture(fixture, look: .light, named: "sheet-\(filling.purpose)-\(setting.name)-light")
    }
  }

  /// What the service Compare with Seamerge leaves in the sheet: one file to compare with the
  /// next, or the sentence about a selection it does not compare.
  @Test(arguments: Look.all)
  func selectionsOfTheServiceArePictured(look: Look) throws {
    let fixture = try WelcomeFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    fixture.controller.compare(with: Filling.compareFilled.files[0])
    try picture(fixture, look: look, named: "sheet-service-one-\(look.name)")

    fixture.controller.showUnsupportedSelection()
    try picture(fixture, look: look, named: "sheet-service-unsupported-\(look.name)")
  }

  @Test func longNamesAreShortenedInTheMiddle() throws {
    let fixture = try WelcomeFixture()
    let folder = URL(filePath: NSHomeDirectory()).appending(
      path: "Projects/a-project-with-a-long-name/Sources/Features/Authentication/Views")
    let files = [
      "LoginViewControllerWithTwoFactorAuthenticationAndRecovery.swift",
      "LoginViewControllerWithTwoFactorAuthenticationAndRecovery copy.swift",
    ].map { folder.appending(path: $0) }
    #expect(fixture.controller.fill(with: files))

    try picture(fixture, look: .light, named: "sheet-long-names-light")
    let labels = try #require(fixture.sheet().fields[.left]).subviews
      .compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews)
      .compactMap { $0 as? NSTextField }
    let name = try #require(labels.first { $0.stringValue == files[0].lastPathComponent })
    #expect(name.lineBreakMode == .byTruncatingMiddle)
    #expect(name.frame.width <= CompareFilesMetrics.fieldSize.width)
  }

  @Test(arguments: [Look.light, .dark])
  func dropTargetIsPicturedWithItsWords(look: Look) throws {
    let files = try SampleFiles()
    let fixture = try WelcomeFixture()
    #expect(fixture.controller.fill(with: [try files.file("LoginView.swift")]))
    fixture.controller.showMergeFiles(nil)
    let sheet = try fixture.sheet()
    #expect(sheet.fill(with: [try files.file("LoginView.swift")]))
    let drag = DragInTest(files: [
      try files.file("base.swift"), try files.file("theirs.swift"), try files.file("mine.swift"),
    ])

    #expect(sheet.operation(forDrag: drag, onto: nil) == .copy)

    #expect(
      try fixture.captions() == ["Drop to Use as A", "Drop to Use as Base", "Drop to Use as B"])
    try picture(fixture, look: look, named: "sheet-drop-target-\(look.name)")
    sheet.dragDidEnd()
    #expect(try fixture.captions() == ["A", "Base", "B"])
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
      NSColor(srgbRed: 0x0A / 255, green: 0x62 / 255, blue: 0xCC / 255, alpha: 1),
      NSColor(srgbRed: 0x1F / 255, green: 0x6F / 255, blue: 0xE0 / 255, alpha: 1),
      NSColor(srgbRed: 0x00 / 255, green: 0x47 / 255, blue: 0xA3 / 255, alpha: 1),
      NSColor(srgbRed: 0x26 / 255, green: 0x72 / 255, blue: 0xE4 / 255, alpha: 1),
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

  private func picture(_ fixture: WelcomeFixture, look: Look, named name: String) throws {
    try fixture.picture(look: look, named: name)
  }
}
