import Foundation
import GitSupport
import SeamergeCLI
import SessionIPC
import Testing

/// A temporary directory with a Git configuration of its own, so that no test reads or writes the
/// configuration of the user or of the system.
struct Sandbox {
  /// The directory, removed when the test ends.
  let directory: URL

  /// The socket the app in the test listens on.
  var socketURL: URL { directory.appending(path: "s.sock") }

  /// The environment of the process without Git's variables, with the configuration redirected
  /// into the sandbox.
  var environment: [String: String] {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = directory.appending(path: "home").path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = directory.appending(path: "home/.gitconfig").path
    return environment
  }

  /// Runs `git` inside the sandbox.
  var git: Git { Git(environment: environment, timeout: .seconds(10)) }

  /// A command that opens nothing and talks to the app in the test.
  func command(
    launcher: any AppLauncher = AppAlreadyRunning(), connectionTimeout: Duration = .seconds(10)
  ) -> SeamergeCommand {
    SeamergeCommand(
      version: "1.2.3", appLauncher: launcher,
      client: SessionClient(socketURL: socketURL, connectionTimeout: connectionTimeout))
  }

  /// Runs `command` with `arguments` in the sandbox, as a shell in `directory` would.
  func run(
    _ arguments: [String], in directory: URL? = nil, command: SeamergeCommand? = nil
  ) async -> CommandResult {
    await (command ?? self.command()).run(
      arguments, workingDirectory: directory ?? self.directory, environment: environment)
  }

  /// Writes `text` into a new file at `path` in the sandbox and returns its location.
  @discardableResult
  func makeFile(_ path: String, text: String = "line\n") throws -> URL {
    let url = directory.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }

  /// Creates a repository in the given scenario of `Scripts/make-test-repo.sh` in `folder`, by
  /// default named after the scenario, and returns the top of its working tree.
  func makeRepository(_ scenario: String, in folder: String? = nil) throws -> URL {
    let repository = directory.appending(path: folder ?? scenario, directoryHint: .isDirectory)
    let result = try runProcess(
      Self.script, arguments: [repository.path, scenario], environment: environment)
    try #require(result.status == 0, "make-test-repo.sh \(scenario): \(result.output)")
    return repository
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
///
/// The name of the directory is short, because the path of a Unix domain socket in it is limited
/// to 103 bytes.
func withSandbox(_ body: (Sandbox) async throws -> Void) async throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "cli-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(
    at: directory.appending(path: "home"), withIntermediateDirectories: true)
  defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
  try await body(Sandbox(directory: directory))
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

/// A launcher for an app that runs already: it does nothing.
struct AppAlreadyRunning: AppLauncher {
  func openApp() async throws {}
}

/// A launcher for an app that cannot be started.
struct AppThatCannotStart: AppLauncher {
  struct LaunchError: LocalizedError {
    var errorDescription: String? { "The application is damaged." }
  }

  func openApp() async throws {
    throw LaunchError()
  }
}
