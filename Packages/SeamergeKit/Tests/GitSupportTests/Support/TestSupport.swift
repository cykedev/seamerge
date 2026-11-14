import Foundation
import GitSupport
import Testing

/// A temporary directory with a Git configuration of its own, so that no test reads or writes
/// the configuration of the user or of the system.
struct Sandbox {
  /// The directory, removed when the test ends.
  let directory: URL

  /// The file that stands in for the global configuration.
  var globalConfiguration: URL { directory.appending(path: "home/.gitconfig") }

  /// The environment of the process without Git's variables, with the configuration redirected
  /// into the sandbox.
  var environment: [String: String] {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = directory.appending(path: "home").path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = globalConfiguration.path
    return environment
  }

  /// Runs `git` inside the sandbox.
  func git(timeout: Duration = .seconds(10), adding variables: [String: String] = [:]) -> Git {
    Git(environment: environment.merging(variables) { $1 }, timeout: timeout)
  }

  /// Creates a repository in the given scenario of `Scripts/make-test-repo.sh` and returns the
  /// top of its working tree.
  func makeRepository(_ scenario: String) throws -> URL {
    let repository = directory.appending(path: scenario, directoryHint: .isDirectory)
    let result = try runProcess(
      Self.script, arguments: [repository.path, scenario], environment: environment)
    try #require(result.status == 0, "make-test-repo.sh \(scenario): \(result.output)")
    return repository
  }

  /// Writes an executable shell script and returns its location.
  func makeExecutable(_ name: String, in folder: String = "bin", script: String) throws -> URL {
    let folderURL = directory.appending(path: folder, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    let url = folderURL.appending(path: name)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  private static let script: URL = {
    var directory = URL(filePath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(
      atPath: directory.appending(path: "Scripts/make-test-repo.sh").path)
    {
      precondition(directory.path != "/", "Scripts/make-test-repo.sh not found above the tests")
      directory.deleteLastPathComponent()
    }
    return directory.appending(path: "Scripts/make-test-repo.sh")
  }()
}

/// Runs `body` with a new sandbox that is removed afterwards.
func withSandbox(_ body: (Sandbox) throws -> Void) throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "GitSupportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: directory.appending(path: "home"), withIntermediateDirectories: true)
  defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
  try body(Sandbox(directory: directory))
}

/// Replaces the global configuration of `sandbox` with `text`.
func writeGlobalConfiguration(_ text: String, in sandbox: Sandbox) throws {
  try Data(text.utf8).write(to: sandbox.globalConfiguration)
}

/// Runs an executable to its end and returns its exit status and its combined output.
func runProcess(
  _ executable: URL, arguments: [String], environment: [String: String], in directory: URL? = nil
) throws -> (status: Int32, output: String) {
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.environment = environment
  process.currentDirectoryURL = directory
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}

extension Git {
  /// The output of a command as text without the final line break, for checking the state of a
  /// repository independently of the code under test.
  func output(_ arguments: [String], in directory: URL) throws -> String {
    let text = String(decoding: try run(arguments, in: directory), as: UTF8.self)
    return text.hasSuffix("\n") ? String(text.dropLast()) : text
  }
}
