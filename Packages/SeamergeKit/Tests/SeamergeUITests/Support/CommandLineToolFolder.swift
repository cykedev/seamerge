import AppKit
import Testing

@testable import Integration
@testable import SeamergeUI

/// A temporary folder that stands in for the Mac in tests of the seamerge command: a copy of
/// Seamerge, the folder of the link, and a folder for Homebrew, with names that a shell must
/// quote.
@MainActor
final class CommandLineToolFolder {
  let folder: URL

  /// The bundle of the copy that runs.
  let bundle: URL

  /// The place of the link, in a folder that does not exist yet.
  let link: URL

  /// The folder Homebrew is installed in.
  let homebrew: URL

  /// The shell that changes the link, without the rights of an administrator.
  let shell = ShellRecorder()

  /// Creates the folder, with the copy of Seamerge at `appPath` inside it.
  init(appPath: String = "Apps/My \"Quoted\" 'Tools' $(touch pwned)/Seamerge.app") throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "CommandLineTool-\(UUID().uuidString)", directoryHint: .isDirectory)
    bundle = folder.appending(path: appPath, directoryHint: .isDirectory)
    link = folder.appending(path: "usr local/bin/seamerge")
    homebrew = folder.appending(path: "homebrew", directoryHint: .isDirectory)
    let helper = AppLocation.helper(inBundle: bundle)
    try FileManager.default.createDirectory(
      at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
  }

  isolated deinit {
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The folder of the test could not be removed")
    }
  }

  /// The helper of the copy that runs.
  var helper: URL { AppLocation.helper(inBundle: bundle) }

  /// The command of the copy that runs, with `problem` as the problem of its place.
  func tool(problem: AppLocation.Problem? = nil) -> CommandLineTool {
    let bundle = bundle
    let downloads = folder.appending(path: "Downloads")
    let location = { () -> AppLocation in
      AppLocation(
        bundle: problem == .temporaryPlace ? downloads.appending(path: "Seamerge.app") : bundle,
        downloads: downloads, isOnReadOnlyVolume: false, hasHelper: problem != .incomplete)
    }
    return CommandLineTool(
      location: location,
      place: CommandLinePlace(link: link, homebrewPrefixes: [homebrew]), shell: shell)
  }

  /// Creates the folder of the link.
  func makeLinkFolder() throws {
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
  }

  /// Puts a link to `destination` at the place of the command.
  func makeLink(to destination: String) throws {
    try makeLinkFolder()
    try FileManager.default.createSymbolicLink(
      atPath: link.path, withDestinationPath: destination)
  }

  /// Puts a file with `text` at the place of the command.
  func makeFile(_ text: String = "#!/bin/sh\necho mine\n") throws {
    try makeLinkFolder()
    try Data(text.utf8).write(to: link)
  }

  /// Installs Seamerge with Homebrew: a folder in the Caskroom and a link in Homebrew's `bin`.
  func installWithHomebrew() throws {
    let bin = homebrew.appending(path: "bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: homebrew.appending(path: "Caskroom/seamerge/0.4.0"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: bin.appending(path: "seamerge").path,
      withDestinationPath: "/Applications/Seamerge.app/Contents/Helpers/seamerge")
  }

  /// What the link names, or `nil` if there is no link.
  var linkDestination: String? {
    do {
      return try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    } catch {
      return nil
    }
  }

  /// Whether the shell ran a command that the user did not ask for, such as the one hidden in
  /// the name of the folder of the copy.
  ///
  /// `touch pwned` would leave its file where the shell runs: in the folder of the test process,
  /// or in the temporary folder for a shell started there.
  var ranSmuggledCommand: Bool {
    [FileManager.default.currentDirectoryPath, FileManager.default.temporaryDirectory.path]
      .contains { FileManager.default.fileExists(atPath: $0 + "/pwned") }
  }
}

/// A shell that runs the scripts through AppleScript as the app does, only without asking for an
/// administrator, records them, can refuse as the dialog of macOS would, and can hold a run
/// while the dialog would be shown.
@MainActor
final class ShellRecorder: AdministratorShell {
  /// The failure of the next run instead of running, if it should fail.
  var refusal: CommandLineToolFailure?

  /// Whether the next run waits for ``release()`` before it runs.
  var holdsNextRun = false

  /// The arguments of each run so far.
  private(set) var runs: [[String]] = []

  /// The prompt of the dialog of each run so far.
  private(set) var prompts: [String] = []

  private let shell = AppleScriptShell(asksForAdministrator: false)
  private var held: CheckedContinuation<Void, Never>?
  private var holdWaiter: CheckedContinuation<Void, Never>?

  func run(_ script: String, arguments: [String], prompt: String)
    async throws(CommandLineToolFailure)
  {
    runs.append(arguments)
    prompts.append(prompt)
    if holdsNextRun {
      holdsNextRun = false
      await withCheckedContinuation { continuation in
        held = continuation
        holdWaiter?.resume()
        holdWaiter = nil
      }
    }
    if let refusal { throw refusal }
    try await shell.run(script, arguments: arguments, prompt: prompt)
  }

  /// Returns once a run waits for ``release()``.
  func waitUntilHeld() async {
    guard held == nil else { return }
    await withCheckedContinuation { holdWaiter = $0 }
  }

  /// Lets the run that waits go on.
  func release() {
    held?.resume()
    held = nil
  }

  /// Runs `script` with `/bin/sh` and `arguments` as its parameters, as the shell of macOS does.
  static func shell(_ script: String, arguments: [String]) -> (status: Int32, error: String) {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", script, "sh"] + arguments
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return (-1, String(describing: error))
    }
    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }
}
