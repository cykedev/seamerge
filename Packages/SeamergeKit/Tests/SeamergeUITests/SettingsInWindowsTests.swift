import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The settings in the session windows: where a new window starts, and what the controls of a
/// window change.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SettingsInWindowsTests {
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
