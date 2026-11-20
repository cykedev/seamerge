import Dispatch
public import Foundation
import os

/// Runs the `git` command-line tool.
///
/// Arguments are passed to the process as a list and never through a shell, so paths and names
/// need no quoting. Each command has a time limit; a command that exceeds it gets `SIGTERM`, and
/// `SIGKILL` if it has not ended half a second later.
public struct Git: Sendable {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "GitSupport")

  /// The `git` executable.
  public let executableURL: URL

  private let environment: [String: String]
  private let timeout: Duration

  /// Creates a runner for the first `git` on the search path of `environment`.
  ///
  /// - Parameters:
  ///   - environment: The environment the commands run in. Its `PATH` decides which `git` runs;
  ///     without one on the path, `/usr/bin/git` runs.
  ///   - timeout: How long a single command may take.
  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    timeout: Duration = .seconds(2)
  ) {
    self.executableURL = Self.executable(onSearchPath: environment["PATH"])
    self.environment = environment
    self.timeout = timeout
  }

  /// Runs `git` with the given arguments and returns what it wrote to its standard output.
  ///
  /// The command runs without a terminal: it cannot prompt, and it does not take the optional
  /// locks of the repository, so that it never blocks a Git command the user is running.
  ///
  /// - Parameters:
  ///   - arguments: The arguments after `git`.
  ///   - directory: The directory the command runs in, or `nil` for the current directory.
  /// - Throws: ``GitError`` if `git` cannot be started, exceeds the time limit or ends with a
  ///   status other than zero.
  public func run(_ arguments: [String], in directory: URL? = nil) throws(GitError) -> Data {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment.merging(
      ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"], uniquingKeysWith: { $1 })
    process.standardInput = FileHandle.nullDevice
    let output = PipeReader()
    let errors = PipeReader()
    process.standardOutput = output.pipe
    process.standardError = errors.pipe

    let finished = DispatchGroup()
    let ended = DispatchSemaphore(value: 0)
    finished.enter()
    process.terminationHandler = { _ in
      ended.signal()
      finished.leave()
    }
    do {
      try process.run()
    } catch {
      finished.leave()
      throw .launchFailed(executable: executableURL.path, reason: error.localizedDescription)
    }
    output.readToEnd(in: finished)
    errors.readToEnd(in: finished)

    // The time limit covers reading the output to its end, because children of the process can
    // hold the pipes open after it ended.
    if finished.wait(timeout: .now() + timeout.dispatchInterval) == .timedOut {
      Self.stop(process, ended: ended)
      Self.logger.error(
        "git \(arguments.joined(separator: " ")) timed out after \(String(describing: timeout))")
      throw .timedOut(arguments: arguments)
    }
    guard process.terminationStatus == 0 else {
      let message = String(decoding: errors.data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw .failed(arguments: arguments, status: process.terminationStatus, message: message)
    }
    return output.data
  }

  /// Runs `git` and returns its standard output as text without the final line break.
  ///
  /// - Throws: ``GitError`` as ``run(_:in:)`` does.
  func text(_ arguments: [String], in directory: URL? = nil) throws(GitError) -> String {
    var text = String(decoding: try run(arguments, in: directory), as: UTF8.self)
    if text.hasSuffix("\n") { text.removeLast() }
    return text
  }

  /// Stops a process: politely first, so that Git can remove its lock files, and by force if it
  /// has not ended after a short grace period.
  private static func stop(_ process: Process, ended: DispatchSemaphore) {
    let gracePeriod = DispatchTimeInterval.milliseconds(500)
    process.terminate()
    guard ended.wait(timeout: .now() + gracePeriod) == .timedOut else { return }
    kill(process.processIdentifier, SIGKILL)
    if ended.wait(timeout: .now() + gracePeriod) == .timedOut {
      logger.error("git \(process.processIdentifier) did not end after SIGKILL")
    }
  }

  private static func executable(onSearchPath searchPath: String?) -> URL {
    let directories = (searchPath ?? "").split(separator: ":").map(String.init)
    for directory in directories where !directory.isEmpty {
      let candidate = URL(filePath: directory, directoryHint: .isDirectory).appending(path: "git")
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return URL(filePath: "/usr/bin/git")
  }
}

extension Duration {
  /// The duration as an interval for Dispatch.
  fileprivate var dispatchInterval: DispatchTimeInterval {
    let (seconds, attoseconds) = components
    return .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
  }
}
