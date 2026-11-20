import AppKit
import Testing

@testable import Integration
@testable import SeamergeUI

/// Draws the sheet Install the seamerge Command for the visual review: every state, in every
/// look for the offer and the way back, with the command shown, and after a failure.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CommandLineToolPicturesTests {
  /// A state of the sheet in a picture.
  enum State: String, CaseIterable, CustomTestStringConvertible {
    case install
    case update
    case remove
    case homebrew
    case otherFile = "other-file"
    case temporaryPlace = "temporary-place"

    var testDescription: String { rawValue }

    var status: CommandLineToolStatus {
      let entry: CommandLineToolStatus.Entry =
        switch self {
        case .install, .temporaryPlace: .none
        case .update: .otherCopy(app: "/Volumes/Seamerge/Seamerge.app")
        case .remove: .thisCopy
        case .homebrew: .homebrew
        case .otherFile: .otherFile(destination: "/usr/local/lib/node_modules/seamerge/cli.js")
        }
      return CommandLineToolStatus(
        entry: entry, link: URL(filePath: "/usr/local/bin/seamerge"),
        helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
        hasLinkFolder: false, problem: self == .temporaryPlace ? .temporaryPlace : nil)
    }
  }

  @Test(arguments: [State.install, .update, .remove], Look.all)
  func sheetIsPicturedInEveryLook(state: State, look: Look) throws {
    try picture(
      sheet(state.status, look: look), look: look,
      named: "command-line-tool-\(state.rawValue)-\(look.name)")
  }

  @Test(arguments: [State.homebrew, .otherFile, .temporaryPlace], [Look.light, .dark])
  func sheetOfTheOtherStatesIsPictured(state: State, look: Look) throws {
    try picture(
      sheet(state.status, look: look), look: look,
      named: "command-line-tool-\(state.rawValue)-\(look.name)")
  }

  @Test(arguments: [Look.light, .dark])
  func sheetWithTheCommandIsPictured(look: Look) throws {
    let sheet = sheet(State.install.status, look: look)
    sheet.commandsDisclosure.performClick(nil)
    try picture(sheet, look: look, named: "command-line-tool-command-\(look.name)")
  }

  @Test func sheetAfterAFailureIsPictured() async throws {
    let sheet = sheet(State.install.status, look: .light)
    sheet.onConfirm = { _ in .notAllowed }
    await sheet.carryOut()
    try picture(sheet, look: .light, named: "command-line-tool-failure-light")
  }

  /// The sheet draws nothing translucent and marks nothing with color alone; these show that.
  @Test(arguments: [
    ("without-color", DisplayOptions(differentiatesWithoutColor: true)),
    ("reduced-transparency", DisplayOptions(reducesTransparency: true)),
  ])
  func sheetIsPicturedWithTheOtherSettings(setting: (name: String, options: DisplayOptions))
    throws
  {
    let sheet = CommandLineToolSheet(
      status: State.install.status, colors: CompareFilesColors(setting.options))
    try picture(sheet, look: .light, named: "command-line-tool-\(setting.name)-light")
  }

  private func sheet(_ status: CommandLineToolStatus, look: Look) -> CommandLineToolSheet {
    CommandLineToolSheet(
      status: status,
      colors: CompareFilesColors(DisplayOptions(increasesContrast: look.increasesContrast)))
  }

  private func picture(_ sheet: CommandLineToolSheet, look: Look, named name: String) throws {
    let window = try #require(sheet.window)
    window.colorSpace = .sRGB
    window.appearance = look.appearance
    window.contentView?.layoutSubtreeIfNeeded()
    try Rendering.write(try Rendering.bitmap(of: window), named: name)
  }
}
