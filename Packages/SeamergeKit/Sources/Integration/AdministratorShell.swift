import Foundation
import os

/// Runs scripts for `/bin/sh` with the rights of an administrator.
@MainActor
package protocol AdministratorShell {
  /// Runs `script` with `arguments` as its positional parameters `$1`, `$2` and so on, after
  /// macOS asked for the rights with `prompt`, and returns once it has ended.
  ///
  /// - Throws: ``CommandLineToolFailure`` if the user or macOS did not allow it, or the script
  ///   ended with a status other than 0.
  func run(_ script: String, arguments: [String], prompt: String)
    async throws(CommandLineToolFailure)
}

/// Why the link of the seamerge command could not be changed.
package enum CommandLineToolFailure: LocalizedError, Equatable {
  /// The user cancelled the dialog of macOS, or is no administrator.
  case notAllowed

  /// Something other than a link to Seamerge lies at the place of the command now.
  case otherFile

  /// The change failed, and the shell said `message`.
  case failed(message: String)

  var errorDescription: String? {
    switch self {
    case .notAllowed:
      String(
        localized: "macOS didn’t allow the change.", bundle: .module,
        comment: "Install the seamerge Command: the dialog for the password was cancelled.")
    case .otherFile:
      String(
        localized: "Another file is in the way.", bundle: .module,
        comment: "Install the seamerge Command: a file appeared where the link goes.")
    case .failed:
      String(
        localized: "The link couldn’t be changed.", bundle: .module,
        comment: "Install the seamerge Command: changing the link failed for another reason.")
    }
  }

  var failureReason: String? {
    if case .failed(let message) = self, !message.isEmpty { message } else { nil }
  }
}

/// Runs scripts through AppleScript's `do shell script`, by default behind the dialog of macOS
/// for an administrator's name and password, so that the app never sees the password.
///
/// `osascript` runs the AppleScript in a process of its own, so that the app goes on drawing
/// while the dialog is shown. The script and its arguments reach AppleScript as the arguments of
/// that process, and AppleScript's `quoted form` puts each into the command line, so that no
/// text is ever parsed as AppleScript or as a command.
package struct AppleScriptShell: AdministratorShell {
  /// Whether the scripts run with the rights of an administrator, which macOS asks for.
  let asksForAdministrator: Bool

  /// The shell behind the dialog of macOS.
  package static let administrator = AppleScriptShell(asksForAdministrator: true)

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "CommandLineTool")

  /// The error numbers of AppleScript that mean the user did not allow the change: a cancelled
  /// dialog, and the refusals of the authorization of macOS.
  private static let refusals: Set<Int> = [-128, -60005, -60006, -60007]

  /// The lines of the AppleScript, whose `run` handler takes the prompt of the dialog, the
  /// script, and the arguments of the script.
  var sourceLines: [String] {
    [
      "on run argv",
      #"set commandLine to "/bin/sh -c " & quoted form of (item 2 of argv) & " sh""#,
      "repeat with argument in rest of rest of argv",
      #"set commandLine to commandLine & " " & quoted form of (argument as text)"#,
      "end repeat",
      asksForAdministrator
        ? "do shell script commandLine with administrator privileges with prompt (item 1 of argv)"
        : "do shell script commandLine",
      "end run",
    ]
  }

  /// Runs `script`; the dialog of macOS says `prompt`, since it would otherwise name
  /// `osascript` as the app that asks.
  package func run(_ script: String, arguments: [String], prompt: String)
    async throws(CommandLineToolFailure)
  {
    let result: (status: Int32, error: String)
    do {
      result = try await Self.osascript(
        sourceLines.flatMap { ["-e", $0] } + [prompt, script] + arguments)
    } catch {
      Self.logger.error("Cannot start osascript: \(String(describing: error))")
      throw .failed(message: error.localizedDescription)
    }
    if let failure = Self.failure(status: result.status, error: result.error) {
      throw failure
    }
  }

  /// What went wrong, as `osascript` ended with `status` and wrote `error`, or `nil` if nothing
  /// did.
  ///
  /// `osascript` ends with 1 and writes the message and the number of the AppleScript error, such
  /// as `execution error: User canceled. (-128)`; for a script that ended with a status other
  /// than 0, the number is that status and the message what the script wrote.
  static func failure(status: Int32, error: String) -> CommandLineToolFailure? {
    guard status != 0 else { return nil }
    let text = error.trimmingCharacters(in: .whitespacesAndNewlines)
    let number = text.firstMatch(of: #/\((-?\d+)\)$/#).flatMap { Int($0.1) }
    if let number, refusals.contains(number) {
      return .notAllowed
    }
    if number == Int(CommandLineToolChange.refusalStatus) {
      return .otherFile
    }
    logger.error("Cannot change the link of the command: \(text)")
    let message =
      text
      .replacing(#/^\d+:\d+: execution error: /#, with: "")
      .replacing(#/ \(-?\d+\)$/#, with: "")
    return .failed(message: message)
  }

  /// Runs `osascript` with `arguments` and returns its exit status and what it wrote as errors,
  /// once it has ended.
  private static func osascript(_ arguments: [String]) async throws -> (
    status: Int32, error: String
  ) {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/osascript")
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    let errors = Pipe()
    process.standardError = errors
    let (ended, end) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { end.yield($0.terminationStatus) }
    try process.run()
    let error = await Task.detached {
      String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }.value
    var iterator = ended.makeAsyncIterator()
    let status = await iterator.next() ?? process.terminationStatus
    return (status, error)
  }
}
