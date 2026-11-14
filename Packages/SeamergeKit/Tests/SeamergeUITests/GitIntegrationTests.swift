import AppKit
import GitSupport
import Testing

@testable import SeamergeUI

/// The line about Git in the window Compare Files and the sheet Set Up Git Integration: what
/// they say for each state, and that nothing changes before the user confirms.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct GitIntegrationTests {
  /// A state of the settings and what the line says for it, and whether it offers to set up.
  struct LineCase: Sendable, CustomTestStringConvertible {
    var status: IntegrationStatus
    var line: String
    var offersSetUp: Bool
    var testDescription: String { line }
  }

  @Test(arguments: [
    LineCase(
      status: .git(merge: .seamerge, diff: .seamerge),
      line: "✓ Git uses Seamerge for merge and diff", offersSetUp: false),
    LineCase(
      status: .git(merge: .none, diff: .none), line: "Git doesn’t use Seamerge yet.",
      offersSetUp: true),
    LineCase(
      status: .kaleidoscope, line: "Git doesn’t use Seamerge yet.", offersSetUp: true),
    LineCase(
      status: .git(merge: .seamerge, diff: .other("opendiff")),
      line: "✓ Git uses Seamerge for merge.", offersSetUp: true),
    LineCase(
      status: .git(merge: .none, diff: .seamerge), line: "✓ Git uses Seamerge for diff.",
      offersSetUp: true),
    LineCase(
      status: .git(
        merge: .movedSeamerge(helper: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
        diff: .seamerge),
      line: "Git points to a copy of Seamerge that has moved.", offersSetUp: true),
    LineCase(
      status: IntegrationStatus(
        git: .notInstalled, tower: nil, backup: nil, problem: nil, commands: []),
      line:
        "Git isn’t installed. Install the Xcode Command Line Tools to use Seamerge with Git.",
      offersSetUp: false),
  ])
  func lineSaysWhetherGitOpensSeamerge(lineCase: LineCase) async throws {
    let (fixture, _) = try integrationFixture(lineCase.status)
    #expect(fixture.controller.gitStatusLabel.stringValue.isEmpty)

    await fixture.controller.readIntegrationStatus()

    #expect(fixture.controller.gitStatusLabel.stringValue == lineCase.line)
    #expect(fixture.controller.gitSetUpButton.isHidden == !lineCase.offersSetUp)
    #expect(fixture.controller.gitSetUpButton.title == "Set Up Git Integration…")
  }

  @Test func withoutGitTheCommandIsDeactivatedAndShowsNoSheet() async throws {
    let (fixture, _) = try integrationFixture(
      IntegrationStatus(git: .notInstalled, tower: nil, backup: nil, problem: nil, commands: []))
    #expect(fixture.controller.canSetUpGitIntegration)

    await fixture.controller.presentGitIntegration()

    #expect(!fixture.controller.canSetUpGitIntegration)
    #expect(fixture.controller.integrationSheet == nil)
  }

  @Test func sheetSaysWhatChangesAndWhatItReplaces() async throws {
    let sheet = try await presentedSheet(for: .kaleidoscope).sheet

    #expect(
      sheet.paragraphs.map(\.stringValue).prefix(4) == [
        "Use Seamerge for Git Merges and Diffs",
        "Git opens Seamerge when you run git mergetool or git difftool. This applies to all "
          + "repositories that don’t set their own tool.",
        "Replaces: Kaleidoscope. Its settings stay in place, so you can switch back.",
        "Git will no longer ask before opening a tool or keep .orig backup files.",
      ])
    #expect(sheet.defaultButton === sheet.confirmButton)
    #expect(sheet.confirmButton.title == "Set Up")
    #expect(sheet.confirmButton.isEnabled)
    #expect(sheet.commandsView.isHidden)
  }

  @Test func sheetNamesBothToolsAndAMovedCopy() {
    #expect(
      IntegrationStatus.git(merge: .other("Kaleidoscope"), diff: .other("FileMerge"))
        .replacedTools
        == "Replaces: Kaleidoscope for merge and FileMerge for diff. Its settings stay in place, "
        + "so you can switch back.")
    #expect(
      IntegrationStatus.git(
        merge: .movedSeamerge(helper: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
        diff: .movedSeamerge(helper: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge")
      ).replacedTools == "Replaces: Seamerge at /Volumes/Seamerge/Seamerge.app.")
    #expect(IntegrationStatus.git(merge: .none, diff: .none).replacedTools == nil)
    #expect(
      IntegrationStatus.git(merge: .none, diff: .none, switches: [.keepBackup]).changedSwitches
        == "Git will no longer keep .orig backup files.")
    #expect(
      IntegrationStatus.git(merge: .none, diff: .none, switches: []).changedSwitches == nil)
  }

  @Test func sheetSaysThatSettingUpReplacesACommandTheUserChanged() {
    let status = IntegrationStatus.git(merge: .seamerge, diff: .changedSeamerge)

    #expect(status.line == "Git runs Seamerge with a command of your own.")
    #expect(status.offersSetUp)
    #expect(status.replacedTools == "Replaces: your own command for Seamerge.")
    #expect(
      IntegrationStatus.git(merge: .seamerge, diff: .outdatedSeamerge).replacedTools == nil)
  }

  @Test func nothingIsWrittenUntilSetUpThenTheLineChanges() async throws {
    let (fixture, store, sheet) = try await presentedSheet(for: .kaleidoscope)
    #expect(await store.writes.isEmpty)

    await sheet.carryOut()

    #expect(await store.writes == ["setUp(addingToTower: false)"])
    #expect(fixture.controller.integrationSheet == nil)
    #expect(
      fixture.controller.gitStatusLabel.stringValue == "✓ Git uses Seamerge for merge and diff")
    #expect(fixture.announcements.last == "✓ Git uses Seamerge for merge and diff")
  }

  @Test func cancelWritesNothing() async throws {
    let (fixture, store, sheet) = try await presentedSheet(for: .kaleidoscope)

    sheet.cancelOperation(nil)

    #expect(fixture.controller.integrationSheet == nil)
    #expect(await store.writes.isEmpty)
    #expect(fixture.controller.gitStatusLabel.stringValue == "Git doesn’t use Seamerge yet.")
  }

  @Test func failedSetUpKeepsTheSheetOpenAndSaysWhy() async throws {
    let (fixture, store, sheet) = try await presentedSheet(for: .kaleidoscope)
    await store.fail(
      with: .git(
        .failed(
          arguments: ["config"], status: 255,
          message: "error: could not lock config file ~/.gitconfig")))

    await sheet.carryOut()

    #expect(fixture.controller.integrationSheet === sheet)
    #expect(!sheet.failureLabel.isHidden)
    #expect(sheet.failureLabel.stringValue == "Git couldn’t save the settings.")
    #expect(
      sheet.failureDetailLabel.stringValue == "error: could not lock config file ~/.gitconfig")
    #expect(sheet.confirmButton.isEnabled)
    #expect(fixture.controller.gitStatusLabel.stringValue == "Git doesn’t use Seamerge yet.")
  }

  @Test(arguments: [
    (AppLocation.Problem.incomplete, "This copy of Seamerge is incomplete. Download it again."),
    (.temporaryPlace, "Move Seamerge to the Applications folder first."),
  ])
  func copyThatGitCannotKeepIsNotSetUp(problem: AppLocation.Problem, text: String) async throws {
    let status = IntegrationStatus.git(
      merge: .other("Kaleidoscope"), diff: .other("Kaleidoscope"), problem: problem)
    let (_, store, sheet) = try await presentedSheet(for: status)

    await sheet.carryOut()

    #expect(!sheet.confirmButton.isEnabled)
    #expect(sheet.paragraphs.map(\.stringValue).contains(text))
    #expect(await store.writes.isEmpty)
  }

  @Test func onceSetUpTheSheetOffersToRemoveAndSaysWhatComesBack() async throws {
    let (fixture, store, sheet) = try await presentedSheet(for: .setUp)

    #expect(
      sheet.paragraphs.map(\.stringValue) == [
        "Git Uses Seamerge for Merge and Diff", "Removing restores: Kaleidoscope.",
      ])
    #expect(sheet.defaultButton === sheet.cancelButton)
    #expect(sheet.confirmButton.title == "Remove")
    #expect(sheet.towerCheckbox == nil)

    await sheet.carryOut()

    #expect(await store.writes == ["remove"])
    #expect(fixture.controller.gitStatusLabel.stringValue == "Git doesn’t use Seamerge yet.")
  }

  @Test func removingSaysWhatItLeavesWithoutAnEarlierTool() {
    let empty = IntegrationStatus.git(
      merge: .seamerge, diff: .seamerge, backup: GitBackup(values: ["merge.tool": String?.none]))
    #expect(empty.sheetMessage == "Removing leaves Git without a merge and diff tool.")
    let byHand = IntegrationStatus.git(merge: .seamerge, diff: .seamerge)
    #expect(
      byHand.sheetMessage
        == "Removing takes Seamerge out of Git’s settings. Git’s general settings for tools "
        + "stay as they are.")
    let two = IntegrationStatus.git(
      merge: .seamerge, diff: .seamerge,
      backup: GitBackup(values: ["merge.tool": "Kaleidoscope", "diff.tool": "FileMerge"]))
    #expect(two.sheetMessage == "Removing restores: Kaleidoscope for merge and FileMerge for diff.")
  }

  @Test func towerIsOfferedOnlyWhenInstalledAndNeverPreselected() async throws {
    let withoutTower = try await presentedSheet(for: .kaleidoscope).sheet
    #expect(withoutTower.towerCheckbox == nil)

    let status = IntegrationStatus.git(
      merge: .other("Kaleidoscope"), diff: .other("Kaleidoscope"),
      tower: .notAdded(.addsToList))
    let (_, store, sheet) = try await presentedSheet(for: status)
    let checkbox = try #require(sheet.towerCheckbox)
    #expect(checkbox.title == "Add Seamerge to Tower")
    #expect(checkbox.state == .off)
    #expect(
      sheet.paragraphs.map(\.stringValue).contains(
        "Adds Seamerge to the list of tools in Tower’s settings and creates a script for it. "
          + "The other tools stay."))

    checkbox.state = .on
    await sheet.carryOut()

    #expect(await store.writes == ["setUp(addingToTower: true)"])
  }

  /// Git uses Seamerge already, and Tower came later or lost its entry.
  @Test func towerIsOfferedAlsoOnceGitUsesSeamerge() async throws {
    let status = IntegrationStatus.git(
      merge: .seamerge, diff: .seamerge, switches: [], tower: .notAdded(.addsToList),
      backup: GitBackup(values: ["merge.tool": "Kaleidoscope", "diff.tool": "Kaleidoscope"]))
    let (fixture, store) = try integrationFixture(status)
    await fixture.controller.readIntegrationStatus()
    #expect(
      fixture.controller.gitStatusLabel.stringValue == "✓ Git uses Seamerge for merge and diff")
    #expect(!fixture.controller.gitSetUpButton.isHidden)
    await fixture.controller.presentGitIntegration()
    let sheet = try #require(fixture.controller.integrationSheet)
    let button = try #require(sheet.towerButton)
    #expect(button.title == "Add to Tower")
    #expect(sheet.defaultButton === button)
    #expect(sheet.confirmButton.title == "Remove")
    #expect(
      sheet.paragraphs.map(\.stringValue).contains(
        "Adds Seamerge to the list of tools in Tower’s settings and creates a script for it. "
          + "The other tools stay."))

    await sheet.carryOut(.addToTower)

    #expect(await store.writes == ["addToTower"])
    #expect(fixture.controller.integrationSheet == nil)
    #expect(fixture.controller.gitSetUpButton.isHidden)
  }

  @Test func untouchedTowerBoxAddsNothingToTower() async throws {
    let status = IntegrationStatus.git(
      merge: .other("Kaleidoscope"), diff: .other("Kaleidoscope"),
      tower: .notAdded(.createsList))
    let (_, store, sheet) = try await presentedSheet(for: status)

    await sheet.carryOut()

    #expect(await store.writes == ["setUp(addingToTower: false)"])
  }

  @Test func showCommandsUnfoldsTheCommandsAndCopiesThem() async throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("seamerge.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let sheet = GitIntegrationSheet(
      status: .kaleidoscope, colors: CompareFilesColors(DisplayOptions()), pasteboard: pasteboard)
    let height = try #require(sheet.window).frame.height

    sheet.commandsDisclosure.performClick(nil)

    #expect(!sheet.commandsView.isHidden)
    #expect(try #require(sheet.window).frame.height > height)
    #expect(sheet.commandsText.string.contains("merge --from-git --base"))
    sheet.copyCommands(nil)
    #expect(
      pasteboard.string(forType: .string)
        == IntegrationStatus.kaleidoscope.commands.joined(separator: "\n") + "\n")
  }

  @Test func appInDownloadsOnADiskImageOrTranslocatedCannotBeSetUp() {
    let downloads = URL(filePath: "/Users/ada/Downloads")
    func problem(_ path: String, readOnly: Bool = false, helper: Bool = true)
      -> AppLocation.Problem?
    {
      AppLocation(
        bundle: URL(filePath: path), downloads: downloads, isOnReadOnlyVolume: readOnly,
        hasHelper: helper
      ).problem
    }
    #expect(problem("/Applications/Seamerge.app") == nil)
    #expect(problem("/Users/ada/Applications/Seamerge.app") == nil)
    #expect(problem("/Users/ada/Downloads/Seamerge.app") == .temporaryPlace)
    #expect(problem("/Volumes/Seamerge/Seamerge.app", readOnly: true) == .temporaryPlace)
    #expect(
      problem("/private/var/folders/x/AppTranslocation/1234/d/Seamerge.app") == .temporaryPlace)
    #expect(problem("/Applications/Seamerge.app", helper: false) == .incomplete)
  }

  /// A window Compare Files for `status` with its sheet shown.
  private func presentedSheet(for status: IntegrationStatus) async throws -> (
    fixture: CompareFilesFixture, store: IntegrationStoreRecorder, sheet: GitIntegrationSheet
  ) {
    let (fixture, store) = try integrationFixture(status)
    await fixture.controller.presentGitIntegration()
    return (fixture, store, try #require(fixture.controller.integrationSheet))
  }
}
