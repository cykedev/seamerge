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

  /// A selected line, as the list in the key window draws it: its quiet text turns to the text
  /// color of a selection, as its names do.
  @Test(arguments: [Look.light, .dark])
  func selectedLineIsPictured(look: Look) async throws {
    let files = try SampleFiles()
    let fixture = try await fixture(look: look, options: DisplayOptions())
    try addRecentComparisons(to: fixture, in: files)
    let table = fixture.controller.recentList.tableView
    table.selectRowIndexes([2], byExtendingSelection: false)
    let row = try #require(table.rowView(atRow: 2, makeIfNecessary: true))
    fixture.window.contentView?.layoutSubtreeIfNeeded()
    #expect(row.isSelected)
    row.isEmphasized = true
    let cell = try #require(row.view(atColumn: 0) as? RecentComparisonCell)

    #expect(cell.backgroundStyle == .emphasized)
    for label in [cell.namesLabel, cell.kindLabel, cell.folderLabel, cell.dateLabel] {
      #expect(label.textColor == .alternateSelectedControlTextColor, "\(label.stringValue)")
    }
    #expect(cell.symbolView.contentTintColor == .alternateSelectedControlTextColor)
    try pictureWithSelection(
      of: row, in: fixture, look: look, named: "welcome-selected-line-\(look.name)")

    row.isEmphasized = false
    #expect(cell.backgroundStyle == .normal)
    #expect(cell.folderLabel.textColor != .alternateSelectedControlTextColor)
  }

  /// The quiet text of a line reaches 4.5 : 1 where it stands: on the list, on the gray of a
  /// line selected in a window in the background, and, in the text color of a selection, on the
  /// accent color of a line selected in the key window.
  @Test(arguments: Look.all)
  func quietTextOfALineIsLegibleSelectedOrNot(look: Look) throws {
    let options = DisplayOptions(increasesContrast: look.increasesContrast)
    let quiet = Contrast.resolve(CompareFilesColors(options).quietText, in: look.appearance)
    let selected = Contrast.resolve(.alternateSelectedControlTextColor, in: look.appearance)
    let pairs: [(String, NSColor?, NSColor)] = [
      ("list", quiet, .windowBackgroundColor),
      ("line in the background", quiet, .unemphasizedSelectedContentBackgroundColor),
      ("selected line", selected, .selectedContentBackgroundColor),
    ]
    for (name, text, background) in pairs {
      let surface = try #require(Contrast.resolve(background, in: look.appearance))
      let ratio = Contrast.ratio(Contrast.over(text, surface), surface)
      #expect(ratio >= 4.5, "\(name): \(String(format: "%.2f", ratio))")
    }
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

  /// Draws the window with `row` on the selection of the key window: caching the display skips
  /// the selection, which the system draws in a layer of its own, so the picture draws it as the
  /// pictures of sidebars do, and the line on top of it.
  private func pictureWithSelection(
    of row: NSTableRowView, in fixture: WelcomeFixture, look: Look, named name: String
  ) throws {
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    let bitmap = try Rendering.bitmap(of: window)
    let frameView = try #require(window.contentView?.superview)
    let cell = try #require(row.view(atColumn: 0) as? RecentComparisonCell)
    var selection = NSColor.selectedContentBackgroundColor
    look.appearance.performAsCurrentDrawingAppearance {
      selection = NSColor.selectedContentBackgroundColor.usingColorSpace(.sRGB) ?? selection
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    selection.setFill()
    NSBezierPath(
      roundedRect: row.convert(row.bounds, to: frameView).insetBy(dx: 10, dy: 0), xRadius: 6,
      yRadius: 6
    ).fill()
    // The line alone, without the window behind it that caching its display would draw.
    let origin = cell.convert(cell.bounds, to: frameView).origin
    let transform = NSAffineTransform()
    transform.translateX(by: origin.x, yBy: origin.y)
    transform.concat()
    if let context = NSGraphicsContext.current {
      cell.displayIgnoringOpacity(cell.bounds, in: context)
    }
    try Rendering.write(bitmap, named: name)
  }

  private func picture(_ fixture: WelcomeFixture, look: Look, named name: String) throws {
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
