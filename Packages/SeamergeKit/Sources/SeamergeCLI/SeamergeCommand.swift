import Foundation
import GitSupport
import SessionIPC
import os

/// The `seamerge` command: hands a merge or a comparison to the app and ends with its outcome.
///
/// Git runs the command as its mergetool and difftool. The command checks the files, finds out
/// what Git is doing, opens the app, sends the session and waits until the user closes the window.
public struct SeamergeCommand: Sendable {
  /// The version `--version` prints.
  public var version: String

  /// Opens the app before the session is sent.
  public var appLauncher: any AppLauncher

  /// Sends the session to the app and waits for its outcome.
  public var client: SessionClient

  /// Creates the command.
  ///
  /// - Parameters:
  ///   - version: The version `--version` prints.
  ///   - appLauncher: Opens the app before the session is sent.
  ///   - client: Sends the session to the app; by default, over the app's socket.
  public init(
    version: String, appLauncher: any AppLauncher, client: SessionClient = SessionClient()
  ) {
    self.version = version
    self.appLauncher = appLauncher
    self.client = client
  }

  /// Runs the command with `arguments` and returns what it writes and its exit status.
  ///
  /// The command waits until the user closes the window, which may take as long as the user wants.
  ///
  /// - Parameters:
  ///   - arguments: The arguments after the name of the command.
  ///   - workingDirectory: The directory relative paths are read from; Git starts the command at
  ///     the top of the working tree.
  ///   - environment: The environment the command runs in, which `git` inherits.
  public func run(
    _ arguments: [String],
    workingDirectory: URL = .currentDirectory(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> CommandResult {
    do {
      let request: SessionRequest
      switch try Invocation(arguments: arguments) {
      case .help:
        return CommandResult(exitStatus: 0, output: HelpText.text)
      case .version:
        return CommandResult(exitStatus: 0, output: "seamerge \(version)\n")
      case .merge(let merge):
        request = .merge(
          try Self.request(for: merge, in: workingDirectory, environment: environment))
      case .diff(let diff):
        request = .diff(try Self.request(for: diff, in: workingDirectory, environment: environment))
      }
      return CommandResult(exitStatus: try await perform(request))
    } catch {
      return CommandResult(
        exitStatus: error.exitStatus, errorOutput: "seamerge: \(error.message)\n")
    }
  }

  /// Opens the app, sends `request` and returns the exit status of its outcome.
  private func perform(_ request: SessionRequest) async throws(CommandError) -> Int32 {
    do {
      try await appLauncher.openApp()
    } catch {
      Logger.seamergeCLI.error("Cannot open the app: \(String(describing: error))")
      throw .appNotOpened(reason: error.localizedDescription)
    }
    do {
      let outcome = try await client.perform(request)
      Logger.seamergeCLI.info("The session ended: \(outcome.rawValue)")
      return outcome.exitStatus
    } catch {
      Logger.seamergeCLI.error("The session failed: \(String(describing: error))")
      throw CommandError(error, request: request)
    }
  }

  private static func request(
    for arguments: MergeArguments, in directory: URL, environment: [String: String]
  ) throws(CommandError) -> SessionRequest.Merge {
    let remote = try FileCheck.readableFile(arguments.remote, option: .remote, in: directory)
    let local = try FileCheck.readableFile(arguments.local, option: .local, in: directory)
    var base = try FileCheck.base(arguments.base, in: directory)
    let output = try FileCheck.outputFile(arguments.output, in: directory)
    let detected = GitContext.detect(
      workingDirectory: directory, mergedFile: output, git: Git(environment: environment))
    if !detected.hasCommonAncestor {
      // Git hands over an empty file as the base of a file both sides added.
      Logger.seamergeCLI.info("The file has no common ancestor; merging without a base")
      base = nil
    }
    var context = SessionRequest.MergeContext(detected)
    if let label = arguments.remoteLabel { context.remote.name = .reference(label) }
    if let label = arguments.localLabel { context.local.name = .reference(label) }
    if let label = arguments.baseLabel { context.base.name = .reference(label) }
    return SessionRequest.Merge(
      base: base, local: local, remote: remote, output: output, context: context,
      isRunByGit: arguments.isFromGit)
  }

  private static func request(
    for arguments: DiffArguments, in directory: URL, environment: [String: String]
  ) throws(CommandError) -> SessionRequest.Diff {
    let left = try FileCheck.readableFile(arguments.left, option: nil, in: directory)
    let right = try FileCheck.readableFile(arguments.right, option: nil, in: directory)
    var context = SessionRequest.DiffContext()
    // Tower passes no path for a change in the working tree; the side in the working tree has it.
    // Git writes its copies into the temporary folder of the environment it runs the tool in.
    let temporaryDirectory =
      environment["TMPDIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
      ?? FileManager.default.temporaryDirectory
    let path =
      arguments.path
      ?? DifftoolContext.inferredPath(
        leftFile: left, rightFile: right, workingDirectory: directory,
        temporaryDirectory: temporaryDirectory)
    if let path {
      context = SessionRequest.DiffContext(
        DifftoolContext.detect(
          path: path, leftFile: left, rightFile: right, workingDirectory: directory,
          environment: environment))
    }
    return SessionRequest.Diff(
      left: left, right: right, displayPath: path, leftLabel: arguments.leftLabel,
      rightLabel: arguments.rightLabel, context: context)
  }
}
