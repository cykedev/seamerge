import AppKit
import Testing

@testable import SeamergeUI

/// The seamerge command: what lies at its place, what installing, updating and removing do in a
/// test folder, that paths reach the shell only as quoted words, and that a file of someone else
/// is never replaced or removed.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CommandLineToolTests {
  @Test func eachStateIsRecognizedInATestFolder() throws {
    func entry(_ prepare: (CommandLineToolFolder) throws -> Void) throws
      -> CommandLineToolStatus.Entry
    {
      let folder = try CommandLineToolFolder()
      try prepare(folder)
      return folder.tool().status.entry
    }

    #expect(try entry { _ in } == .none)
    #expect(try entry { try $0.makeLink(to: $0.helper.path) } == .thisCopy)
    #expect(
      try entry { folder in
        let relative = "../../" + folder.helper.path.dropFirst(folder.folder.path.count + 1)
        try folder.makeLink(to: relative)
      } == .thisCopy)
    #expect(
      try entry { try $0.makeLink(to: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge") }
        == .otherCopy(app: "/Volumes/Seamerge/Seamerge.app"))
    #expect(try entry { try $0.installWithHomebrew() } == .homebrew)
    #expect(try entry { try $0.makeFile() } == .otherFile(destination: nil))
    #expect(try entry { try $0.makeLink(to: "/bin/ls") } == .otherFile(destination: "/bin/ls"))
    #expect(
      try entry { folder in
        try FileManager.default.createDirectory(at: folder.link, withIntermediateDirectories: true)
      } == .otherFile(destination: nil))
  }

  @Test func linkThatHomebrewMadeAtThePlaceOfTheCommandIsHomebrews() throws {
    let folder = try CommandLineToolFolder()
    try folder.installWithHomebrew()
    let tool = CommandLineTool(
      location: { AppLocation.current(bundle: folder.bundle) },
      place: CommandLinePlace(
        link: folder.homebrew.appending(path: "bin/seamerge"), homebrewPrefixes: [folder.homebrew]),
      shell: folder.shell)

    #expect(tool.status.entry == .homebrew)
    #expect(!tool.isInstalled)
  }

  @Test func onlyTheLinkOfThisCopyCountsAsInstalled() throws {
    let folder = try CommandLineToolFolder()
    #expect(!folder.tool().isInstalled)

    try folder.makeLink(to: folder.helper.path)

    #expect(folder.tool().isInstalled)
  }

  @Test func installMakesTheFolderAndTheLinkAndRunsNothingHiddenInThePaths() async throws {
    let folder = try CommandLineToolFolder()
    let status = folder.tool().status
    #expect(!status.hasLinkFolder)

    try await install(in: folder)

    #expect(folder.linkDestination == folder.helper.path)
    #expect(folder.tool().status.entry == .thisCopy)
    #expect(!folder.ranSmuggledCommand)
  }

  @Test func updatePointsTheLinkOfAMovedCopyToThisOne() async throws {
    let folder = try CommandLineToolFolder()
    try folder.makeLink(to: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge")

    try await install(in: folder)

    #expect(folder.linkDestination == folder.helper.path)
  }

  @Test func removeDeletesTheLinkAndNothingElse() async throws {
    let folder = try CommandLineToolFolder()
    try await install(in: folder)

    try await folder.shell.run(
      CommandLineToolChange.remove.script, arguments: [folder.helper.path, folder.link.path],
      prompt: "")

    #expect(folder.linkDestination == nil)
    #expect(folder.tool().status.entry == .none)
    #expect(FileManager.default.isExecutableFile(atPath: folder.helper.path))
    #expect(FileManager.default.fileExists(atPath: folder.link.deletingLastPathComponent().path))
  }

  /// Something of someone else at the place of the command.
  enum OtherFile: String, CaseIterable, CustomTestStringConvertible {
    case file
    case link
    case folder

    var testDescription: String { rawValue }
  }

  @Test(arguments: OtherFile.allCases)
  func fileOfSomeoneElseIsNeverReplacedOrRemoved(otherFile: OtherFile) async throws {
    let folder = try CommandLineToolFolder()
    switch otherFile {
    case .file: try folder.makeFile()
    case .link: try folder.makeLink(to: "/bin/ls")
    case .folder:
      try FileManager.default.createDirectory(at: folder.link, withIntermediateDirectories: true)
    }
    let before = try FileManager.default.attributesOfItem(atPath: folder.link.path)
    #expect(!folder.tool().status.canConfirm)

    for change in [CommandLineToolChange.install, .remove] {
      await #expect(throws: CommandLineToolFailure.otherFile) {
        try await folder.shell.run(
          change.script, arguments: [folder.helper.path, folder.link.path], prompt: "")
      }
    }

    let after = try FileManager.default.attributesOfItem(atPath: folder.link.path)
    #expect(after[.type] as? FileAttributeType == before[.type] as? FileAttributeType)
    #expect(after[.systemFileNumber] as? Int == before[.systemFileNumber] as? Int)
    if otherFile == .file {
      #expect(try String(contentsOf: folder.link, encoding: .utf8) == "#!/bin/sh\necho mine\n")
    }
    if otherFile == .link {
      #expect(folder.linkDestination == "/bin/ls")
    }
  }

  @Test func typedCommandsMakeTheSameLinkWithPathsAShellMustQuote() throws {
    let folder = try CommandLineToolFolder()
    let commands = CommandLineToolChange.typedCommands(for: folder.tool().status)
    #expect(commands.count == 2)
    #expect(commands.first?.hasPrefix("sudo mkdir -p '") == true)

    // `sudo` runs its arguments as they are, without the rights it would ask for.
    let result = ShellRecorder.shell(
      "sudo() { \"$@\"; }\n" + commands.joined(separator: "\n"), arguments: [])

    #expect(result.status == 0, "\(result.error)")
    #expect(folder.linkDestination == folder.helper.path)
    #expect(!folder.ranSmuggledCommand)
  }

  @Test func typedCommandQuotesOnlyWhatNeedsIt() {
    let status = CommandLineToolStatus(
      entry: .none, link: URL(filePath: "/usr/local/bin/seamerge"),
      helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
      hasLinkFolder: true, problem: nil)

    #expect(
      CommandLineToolChange.typedCommands(for: status) == [
        "sudo ln -sf /Applications/Seamerge.app/Contents/Helpers/seamerge /usr/local/bin/seamerge"
      ])
    #expect(CommandLineToolChange.shellQuoted("/Apps/Ada's Tools") == #"'/Apps/Ada'\''s Tools'"#)
  }

  @Test func appleScriptHandsEveryArgumentToTheShellAsOneWordUnchanged() async throws {
    let folder = try CommandLineToolFolder()
    let output = folder.folder.appending(path: "words")
    let marker = folder.folder.appending(path: "smuggled").path
    let words = [
      "-n", "--", "two words", "'single'", "\"double\"", "$(touch '\(marker)')",
      "`touch '\(marker)'`", "; touch '\(marker)'", "line\nbreak", "trailing\n\n",
      "back\\slash", "*?[a]", "Grüße", "",
    ]
    let script = #"out=$1; shift; for word; do printf '%s\0' "$word"; done > "$out""#

    try await AppleScriptShell(asksForAdministrator: false).run(
      script, arguments: [output.path] + words, prompt: "")

    let written = try Data(contentsOf: output)
    #expect(
      written.split(separator: 0, omittingEmptySubsequences: false).dropLast().map {
        String(decoding: $0, as: UTF8.self)
      } == words)
    #expect(!FileManager.default.fileExists(atPath: marker))
  }

  @Test func appleScriptTellsARefusalOfTheScriptFromAFailure() async {
    let shell = AppleScriptShell(asksForAdministrator: false)

    await #expect(throws: CommandLineToolFailure.otherFile) {
      try await shell.run("exit 3", arguments: [], prompt: "")
    }
    await #expect(throws: CommandLineToolFailure.failed(message: "no space left")) {
      try await shell.run("echo 'no space left' >&2; exit 5", arguments: [], prompt: "")
    }
  }

  @Test func answersOfOsascriptBecomeTheFailuresOfTheSheet() {
    func failure(_ error: String, status: Int32 = 1) -> CommandLineToolFailure? {
      AppleScriptShell.failure(status: status, error: error)
    }

    #expect(failure("", status: 0) == nil)
    #expect(failure("7:30: execution error: User canceled. (-128)\n") == .notAllowed)
    #expect(
      failure(
        "7:30: execution error: The administrator user name or password was "
          + "incorrect. (-60005)") == .notAllowed)
    #expect(
      failure("7:76: execution error: The command exited with a non-zero status. (3)")
        == .otherFile)
    #expect(
      failure("7:76: execution error: ln: /usr/local/bin: Read-only file system (1)")
        == .failed(message: "ln: /usr/local/bin: Read-only file system"))
  }

  @Test func dialogNamesSeamergeAndWhatItDoes() {
    func prompt(_ entry: CommandLineToolStatus.Entry) -> String {
      CommandLineToolStatus(
        entry: entry, link: URL(filePath: "/usr/local/bin/seamerge"),
        helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
        hasLinkFolder: true, problem: nil
      ).dialogPrompt
    }

    #expect(prompt(.none) == "Seamerge wants to install the seamerge command in /usr/local/bin.")
    #expect(
      prompt(.otherCopy(app: "/Volumes/Seamerge/Seamerge.app"))
        == "Seamerge wants to update the seamerge command in /usr/local/bin.")
    #expect(
      prompt(.thisCopy) == "Seamerge wants to remove the seamerge command from /usr/local/bin.")
  }

  @Test func dialogAsksForAnAdministratorWithAPromptOfItsOwn() {
    #expect(
      AppleScriptShell.administrator.sourceLines.contains(
        "do shell script commandLine with administrator privileges with prompt (item 1 of argv)"))
    #expect(
      !AppleScriptShell(asksForAdministrator: false).sourceLines.joined().contains(
        "administrator"))
  }

  @Test func linkThatNamesTheHelperThroughALinkedFolderIsThisCopy() throws {
    let folder = try CommandLineToolFolder()
    let alias = folder.folder.appending(path: "Alias")
    try FileManager.default.createSymbolicLink(
      at: alias, withDestinationURL: folder.bundle.deletingLastPathComponent())
    let helperThroughAlias = alias.appending(path: "Seamerge.app/Contents/Helpers/seamerge")
    #expect(FileManager.default.isExecutableFile(atPath: helperThroughAlias.path))

    try folder.makeLink(to: helperThroughAlias.path)

    #expect(folder.tool().status.entry == .thisCopy)
  }

  @Test func sheetIsLockedAndShowsProgressWhileTheDialogOfMacOSWaits() async throws {
    let (folder, _, tool, sheet) = try presentedSheet()
    folder.shell.holdsNextRun = true

    let run = Task { await sheet.carryOut() }
    await folder.shell.waitUntilHeld()

    #expect(sheet.confirmButton?.isEnabled == false)
    #expect(!sheet.cancelButton.isEnabled)
    #expect(!sheet.progressIndicator.isHidden)
    sheet.cancelOperation(nil)
    #expect(tool.sheet === sheet)

    folder.shell.release()
    await run.value

    #expect(tool.sheet == nil)
    #expect(tool.isInstalled)
    #expect(sheet.progressIndicator.isHidden)
  }

  @Test func nothingChangesUntilInstallThenTheSheetEndsAndSaysTheNewState() async throws {
    let (folder, fixture, tool, sheet) = try presentedSheet()
    #expect(folder.shell.runs.isEmpty)
    #expect(!fixture.controller.canShowCommandLineTool(tool))

    await sheet.carryOut()

    #expect(folder.shell.runs == [[folder.helper.path, folder.link.path]])
    #expect(
      folder.shell.prompts == [
        "Seamerge wants to install the seamerge command in "
          + "\(folder.link.deletingLastPathComponent().path)."
      ])
    #expect(tool.sheet == nil)
    #expect(fixture.controller.canShowCommandLineTool(tool))
    #expect(tool.isInstalled)
    #expect(fixture.announcements.last == "The seamerge command is installed.")
  }

  @Test func removeEndsTheSheetAndSaysTheNewState() async throws {
    let (folder, fixture, tool, sheet) = try presentedSheet { try $0.makeLink(to: $0.helper.path) }
    #expect(sheet.defaultButton === sheet.cancelButton)

    await sheet.carryOut()

    #expect(folder.linkDestination == nil)
    #expect(!tool.isInstalled)
    #expect(fixture.announcements.last == "The seamerge command is removed.")
  }

  @Test func cancelChangesNothing() throws {
    let (folder, fixture, tool, sheet) = try presentedSheet()

    sheet.cancelOperation(nil)

    #expect(tool.sheet == nil)
    #expect(folder.shell.runs.isEmpty)
    #expect(folder.linkDestination == nil)
    #expect(fixture.announcements.isEmpty)
  }

  @Test func refusalOfMacOSKeepsTheSheetOpenAndSaysWhy() async throws {
    let (folder, fixture, tool, sheet) = try presentedSheet()
    folder.shell.refusal = .notAllowed

    await sheet.carryOut()

    #expect(tool.sheet === sheet)
    #expect(!sheet.failureLabel.isHidden)
    #expect(sheet.failureLabel.stringValue == "macOS didn’t allow the change.")
    #expect(sheet.failureDetailLabel.isHidden)
    #expect(sheet.confirmButton?.isEnabled == true)
    #expect(folder.linkDestination == nil)
    #expect(fixture.announcements.isEmpty)
  }

  @Test func fileThatAppearedMeanwhileIsKeptAndTheSheetSaysSo() async throws {
    let (folder, _, tool, sheet) = try presentedSheet()
    try folder.makeFile()

    await sheet.carryOut()

    #expect(tool.sheet === sheet)
    #expect(sheet.failureLabel.stringValue == "Another file is in the way.")
    #expect(try String(contentsOf: folder.link, encoding: .utf8) == "#!/bin/sh\necho mine\n")
  }

  /// A state, and what the sheet says and offers for it.
  struct SheetCase: Sendable, CustomTestStringConvertible {
    var name: String
    var title: String
    var button: String?
    var isEnabled: Bool
    var hasCommand: Bool
    var lastParagraph: String
    var testDescription: String { name }
  }

  @Test(arguments: [
    SheetCase(
      name: "nothing", title: "Install the seamerge Command", button: "Install", isEnabled: true,
      hasCommand: true,
      lastParagraph: "If Terminal doesn’t find seamerge, add /usr/local/bin to "
        + "the PATH of your shell."),
    SheetCase(
      name: "moved", title: "Update the seamerge Command", button: "Update", isEnabled: true,
      hasCommand: true,
      lastParagraph: "If Terminal doesn’t find seamerge, add /usr/local/bin to "
        + "the PATH of your shell."),
    SheetCase(
      name: "installed", title: "The seamerge Command Is Installed", button: "Remove",
      isEnabled: true, hasCommand: false,
      lastParagraph: "You can compare files in Terminal, for example seamerge old.txt new.txt. "
        + "Removing deletes the link at /usr/local/bin/seamerge. macOS asks for an "
        + "administrator’s name and password."),
    SheetCase(
      name: "homebrew", title: "The seamerge Command Is Installed", button: nil, isEnabled: false,
      hasCommand: false, lastParagraph: "Homebrew installed the seamerge command."),
    SheetCase(
      name: "other file", title: "Install the seamerge Command", button: "Install",
      isEnabled: false, hasCommand: false,
      lastParagraph: "/usr/local/bin/seamerge is a link to /opt/tools/seamerge. Seamerge doesn’t "
        + "replace it."),
    SheetCase(
      name: "temporary place", title: "Install the seamerge Command", button: "Install",
      isEnabled: false, hasCommand: true,
      lastParagraph: "Move Seamerge to the Applications folder first."),
  ])
  func sheetSaysTheStateAndOffersOnlyWhatIsAllowed(sheetCase: SheetCase) {
    let entry: CommandLineToolStatus.Entry =
      switch sheetCase.name {
      case "moved": .otherCopy(app: "/Volumes/Seamerge/Seamerge.app")
      case "installed": .thisCopy
      case "homebrew": .homebrew
      case "other file": .otherFile(destination: "/opt/tools/seamerge")
      default: .none
      }
    let sheet = CommandLineToolSheet(
      status: CommandLineToolStatus(
        entry: entry, link: URL(filePath: "/usr/local/bin/seamerge"),
        helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
        hasLinkFolder: true, problem: sheetCase.name == "temporary place" ? .temporaryPlace : nil),
      colors: CompareFilesColors(DisplayOptions()))

    #expect(sheet.paragraphs.first?.stringValue == sheetCase.title)
    #expect(sheet.paragraphs.last?.stringValue == sheetCase.lastParagraph)
    #expect(sheet.confirmButton?.title == sheetCase.button)
    #expect((sheet.confirmButton?.isEnabled ?? false) == sheetCase.isEnabled)
    #expect((sheet.commandsDisclosure.superview != nil) == sheetCase.hasCommand)
    #expect(sheet.cancelButton.title == (sheetCase.button == nil ? "OK" : "Cancel"))
    #expect(sheet.window?.accessibilityTitle() == sheetCase.title)
  }

  @Test func showCommandUnfoldsTheCommandAndCopiesIt() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("seamerge.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let folder = try CommandLineToolFolder()
    let status = folder.tool().status
    let sheet = CommandLineToolSheet(
      status: status, colors: CompareFilesColors(DisplayOptions()), pasteboard: pasteboard)
    let height = try #require(sheet.window).frame.height
    #expect(sheet.commandsView.isHidden)

    sheet.commandsDisclosure.performClick(nil)

    #expect(!sheet.commandsView.isHidden)
    #expect(try #require(sheet.window).frame.height > height)
    let commands = CommandLineToolChange.typedCommands(for: status)
    #expect(sheet.commandsText.string == commands.joined(separator: "\n"))
    sheet.copyCommands(nil)
    #expect(pasteboard.string(forType: .string) == commands.joined(separator: "\n") + "\n")
  }

  private func install(in folder: CommandLineToolFolder) async throws {
    try await folder.shell.run(
      CommandLineToolChange.install.script, arguments: [folder.helper.path, folder.link.path],
      prompt: "")
  }

  /// A test folder prepared by `prepare`, and the sheet of its command on a window Compare
  /// Files.
  private func presentedSheet(
    _ prepare: (CommandLineToolFolder) throws -> Void = { _ in }
  ) throws -> (
    folder: CommandLineToolFolder, fixture: CompareFilesFixture, tool: CommandLineTool,
    sheet: CommandLineToolSheet
  ) {
    let folder = try CommandLineToolFolder()
    try prepare(folder)
    let fixture = try CompareFilesFixture()
    let tool = folder.tool()
    tool.presentSheet(
      on: fixture.window, colors: CompareFilesColors(DisplayOptions()),
      announce: fixture.controller.announce)
    return (folder, fixture, tool, try #require(tool.sheet))
  }
}
