import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The settings in the session windows: the text settings take effect in every open window at
/// once, and the others are where a new window starts.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SettingsInWindowsTests {
  @Test func textSettingsTakeEffectInEveryOpenWindowAtOnce() async throws {
    let settings = UserSettings.private()
    let merge = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    let diff = try Windows.controller(for: try await SampleDiffs.greeting(), settings: settings)
    let family = try #require(UserSettings.monospacedFamilies.first, "a font of fixed width")

    settings.fontFamily = family
    settings.fontSize = 16
    settings.lineSpacing = .spacious
    settings.tabWidth = 8

    for controller in [merge, diff] {
      for pane in Windows.panes(of: controller) {
        #expect(pane.theme.font.familyName == family)
        #expect(pane.theme.font.pointSize == 16)
        #expect(pane.theme.lineHeightMultiple == LineSpacing.spacious.multiple)
        #expect(pane.theme.rowHeight == (16 * 1.7).rounded(.up))
        #expect(pane.theme.tabWidth == 8)
      }
      #expect(controller.fontSize == 16)
    }
  }

  @Test func newWindowDrawsItsCodeAsTheSettingsSay() async throws {
    let settings = UserSettings.private()
    settings.fontSize = 11
    settings.lineSpacing = .compact
    settings.tabWidth = 2

    let controller = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: settings)

    for pane in Windows.panes(of: controller) {
      #expect(pane.theme.font.pointSize == 11)
      #expect(pane.theme.rowHeight == (11 * 1.3).rounded(.up))
      #expect(pane.theme.tabWidth == 2)
    }
  }

  @Test func sizeBeyondTheRangeIsDrawnAndKeptAsTheNearestWithin() async throws {
    let settings = UserSettings.private()
    let controller = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: settings)

    settings.fontSize = 40

    #expect(controller.fontSize == UserSettings.fontSizes.upperBound)
    #expect(settings.defaults.double(forKey: "CodeFontSize") == 24)
  }

  @Test func zoomOfAWindowLastsUntilTheSizeInTheSettingsChanges() async throws {
    let settings = UserSettings.private()
    let controller = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: settings)
    controller.zoomIn(nil)
    controller.zoomIn(nil)
    #expect(controller.fontSize == 16)

    settings.lineSpacing = .compact
    #expect(controller.fontSize == 16, "another setting keeps the zoom")
    #expect(controller.layout.sourcePanes[0].pane.theme.rowHeight == (16 * 1.3).rounded(.up))

    settings.fontSize = 12
    #expect(controller.fontSize == 12)
    #expect(controller.canPerform(.actualSize) == false)
    controller.zoomIn(nil)
    controller.actualSize(nil)
    #expect(controller.fontSize == 12, "Actual Size is the size of the settings")
  }

  @Test func changingTheTextKeepsTheLineAtTheReadingLine() async throws {
    let settings = UserSettings.private()
    let controller = try Windows.controller(
      for: try await SampleMerges.manyBlocks(), settings: settings)
    let b = try #require(controller.layout.sourcePane(.b))
    controller.presentation.jump(to: 20)
    let line = b.rowAtReadingLine.row

    settings.lineSpacing = .spacious
    settings.fontSize = 18

    #expect(abs(b.rowAtReadingLine.row - line) <= 1)
  }

  @Test func newMergeHidesTheBaseAndShowsInvisiblesAsTheSettingsSay() async throws {
    let settings = UserSettings.private()
    settings.showsBase = false
    settings.showsInvisibles = true

    let controller = try Windows.controller(
      for: try await SampleMerges.helloWorld(), settings: settings)

    #expect(!controller.layout.showsBase)
    #expect(controller.content.footer.button(of: .base)?.state == .off)
    #expect(Windows.panes(of: controller).allSatisfy { $0.showsInvisibles })
    #expect(controller.content.footer.button(of: .invisibles)?.state == .on)
  }

  @Test func switchesOfAWindowLeaveTheSettingsAndTheOtherWindows() async throws {
    let settings = UserSettings.private()
    let session = try await SampleMerges.helloWorld()
    let first = try Windows.controller(for: session, settings: settings)
    let second = try Windows.controller(for: session, settings: settings)

    first.toggleBase(nil)
    first.toggleInvisibles(nil)

    #expect(!first.layout.showsBase)
    #expect(second.layout.showsBase)
    #expect(Windows.panes(of: second).allSatisfy { !$0.showsInvisibles })
    #expect(settings.showsBase && !settings.showsInvisibles)
  }

  @Test func choosingStaysOnTheConflictWhenTheSettingsSaySo() async throws {
    let settings = UserSettings.private()
    settings.goesToNextConflict = false
    let controller = try Windows.controller(
      for: try await EditingFixture.nineBlocks(), settings: settings)
    controller.presentation.setCurrentBlock(1)

    controller.perform(.useB)

    #expect(controller.presentation.currentBlock == 1)
    #expect(controller.presentation.navigation.isOpenConflict[1] == false)
  }

  @Test func subtitleNamesTheModeOnlyWhereItDiffersFromThatOfANewWindow() async throws {
    let settings = UserSettings.private()
    settings.comparisonMode = .exact
    let exact = try await SampleMerges.helloWorld().recomputed(
      options: ComparisonOptions(mode: .exact))

    let controller = try Windows.controller(for: exact, settings: settings)
    #expect(controller.window?.accessibilityTitle()?.contains("Compared exactly") == false)

    let other = try Windows.controller(for: try await SampleMerges.helloWorld(), settings: settings)
    #expect(
      other.window?.accessibilityTitle()?.contains("Whitespace changes ignored") == true)
  }

  @Test func windowOfSeveralFilesComparesInTheModeOfTheSettings() async throws {
    let settings = UserSettings.private()
    settings.comparisonMode = .ignoreAllWhitespace
    let files = try SampleCollections.commit(in: try SampleCollections.folder())

    let controller = try await Windows.controller(
      for: FileCollection(files: files), settings: settings)

    #expect(controller.comparisonOptions.mode == .ignoreAllWhitespace)
  }
}
