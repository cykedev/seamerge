import Foundation
import Testing

/// A repository that `Scripts/make-test-repo.sh` prepares in a temporary folder, with the
/// configuration of the user and the system out of reach.
struct TestRepository {
  /// The top of the working tree.
  let directory: URL

  /// The folder that holds the repository and stands in for the home folder.
  private let folder: URL

  /// Prepares the repository in `scenario`; ``remove()`` takes it away.
  init(_ scenario: String) throws {
    folder = FileManager.default.temporaryDirectory
      .appending(path: "MergeModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    directory = folder.appending(path: scenario, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    do {
      let made = try run(Self.script, [directory.path, scenario])
      try #require(made.status == 0, "make-test-repo.sh \(scenario): \(made.output)")
    } catch {
      remove()
      throw error
    }
  }

  /// The text of an object that Git names by `revision`, such as `HEAD:file` or the stage
  /// `:2:file` of a conflicted file.
  func text(of revision: String) throws -> String {
    let git = try #require(Git.executable, "Git is not installed")
    let shown = try run(git, ["show", revision], in: directory)
    try #require(shown.status == 0, "git show \(revision): \(shown.output)")
    return shown.output
  }

  /// Removes the repository and its folder.
  func remove() {
    #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) }
  }

  /// The environment without Git's variables, with the configuration of the user and the system
  /// out of reach.
  private var environment: [String: String] {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = folder.path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    return environment
  }

  /// Runs an executable to its end and returns its exit status and its standard output, with
  /// the standard error after it.
  ///
  /// The standard error goes into a file, which never fills as a pipe does while the standard
  /// output is read.
  private func run(
    _ executable: URL, _ arguments: [String], in directory: URL? = nil
  ) throws -> (status: Int32, output: String) {
    let errorFile = folder.appending(path: "stderr-\(UUID().uuidString)")
    try #require(FileManager.default.createFile(atPath: errorFile.path, contents: nil))
    defer { try? FileManager.default.removeItem(at: errorFile) }
    let error = try FileHandle(forWritingTo: errorFile)
    defer { try? error.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = directory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let printed = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let complaint = try Data(contentsOf: errorFile)
    return (process.terminationStatus, String(decoding: printed + complaint, as: UTF8.self))
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
