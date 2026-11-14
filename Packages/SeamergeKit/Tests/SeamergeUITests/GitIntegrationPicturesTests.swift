import AppKit
import GitSupport
import Testing

@testable import SeamergeUI

/// Draws the sheet Set Up Git Integration and the line about Git for the visual review: the
/// offer and the way back, in every look, with the commands shown, with Tower, and after a
/// failure.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct GitIntegrationPicturesTests {
  /// A state of the sheet in a picture.
  enum State: String, CaseIterable, CustomTestStringConvertible {
    case offer
    case remove
    case towerLater = "tower-later"

    var testDescription: String { rawValue }

    var status: IntegrationStatus {
      switch self {
      case .offer:
        .git(
          merge: .other("Kaleidoscope"), diff: .other("Kaleidoscope"),
          tower: .notAdded(.addsToList))
      case .towerLater:
        .git(
          merge: .seamerge, diff: .seamerge, switches: [], tower: .notAdded(.createsList),
          backup: GitBackup(values: ["merge.tool": "Kaleidoscope", "diff.tool": "Kaleidoscope"]))
      case .remove:
        .git(
          merge: .seamerge, diff: .seamerge, switches: [], tower: .added,
          backup: GitBackup(values: ["merge.tool": "Kaleidoscope", "diff.tool": "Kaleidoscope"]))
      }
    }
  }

  @Test(arguments: State.allCases, Look.all)
  func sheetIsPictured(state: State, look: Look) throws {
    let sheet = GitIntegrationSheet(
      status: state.status,
      colors: CompareFilesColors(DisplayOptions(increasesContrast: look.increasesContrast)))
    try picture(sheet, look: look, named: "git-integration-\(state.rawValue)-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func sheetWithTheCommandsIsPictured(look: Look) throws {
    let sheet = GitIntegrationSheet(
      status: State.offer.status, colors: CompareFilesColors(DisplayOptions()))
    sheet.commandsDisclosure.performClick(nil)
    try picture(sheet, look: look, named: "git-integration-commands-\(look.name)")
  }

  @Test func sheetOfACopyThatCannotBeSetUpIsPictured() throws {
    let sheet = GitIntegrationSheet(
      status: .git(
        merge: .movedSeamerge(helper: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
        diff: .other("FileMerge"), switches: [.keepBackup], problem: .temporaryPlace),
      colors: CompareFilesColors(DisplayOptions()))
    try picture(sheet, look: .light, named: "git-integration-temporary-place-light")
  }

  @Test func sheetAfterAFailureIsPictured() async throws {
    let (fixture, store) = try integrationFixture(State.offer.status)
    await fixture.controller.presentGitIntegration()
    let sheet = try #require(fixture.controller.integrationSheet)
    await store.fail(
      with: .git(
        .failed(
          arguments: [], status: 255,
          message: "error: could not lock config file /Users/ada/.gitconfig: File exists")))
    await sheet.carryOut()
    try picture(sheet, look: .light, named: "git-integration-failure-light")
  }

  /// The sheet draws nothing translucent and marks nothing with color alone; these show that.
  @Test(arguments: [
    ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
    ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
  ])
  func sheetIsPicturedWithTheOtherSettings(setting: (name: String, options: DisplayOptions))
    throws
  {
    let sheet = GitIntegrationSheet(
      status: State.offer.status, colors: CompareFilesColors(setting.options))
    try picture(sheet, look: .light, named: "git-integration-\(setting.name)-light")
  }

  @Test(
    arguments: [
      ("not-set-up", IntegrationStatus.kaleidoscope),
      ("set-up", IntegrationStatus.setUp),
      (
        "no-git",
        IntegrationStatus(git: .notInstalled, tower: nil, backup: nil, problem: nil, commands: [])
      ),
    ], [Look.light, .dark])
  func lineIsPictured(state: (name: String, status: IntegrationStatus), look: Look) async throws {
    let (fixture, _) = try integrationFixture(state.status)
    await fixture.controller.readIntegrationStatus()
    let window = fixture.window
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(
      try Rendering.bitmap(of: window), named: "compare-files-git-\(state.name)-\(look.name)")
  }

  private func picture(_ sheet: GitIntegrationSheet, look: Look, named name: String) throws {
    let window = try #require(sheet.window)
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
