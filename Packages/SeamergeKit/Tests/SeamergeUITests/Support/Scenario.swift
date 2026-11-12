import Foundation
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// A merge as `git mergetool` hands it to the tool, in a repository that
/// `Scripts/make-test-repo.sh` prepares: the three stages of the conflicted file and what Git is
/// doing.
struct Scenario: Sendable, CustomTestStringConvertible {
  /// The name of the scenario in `make-test-repo.sh`.
  let name: String

  /// The conflicted file, relative to the top of the working tree.
  let file: String

  /// The merge scenarios of `make-test-repo.sh`; the comparisons belong to the diff window.
  static let merges = [
    Scenario(name: "merge", file: "story.txt"),
    Scenario(name: "rebase", file: "notes.txt"),
    Scenario(name: "cherry-pick", file: "story.txt"),
    Scenario(name: "revert", file: "story.txt"),
    Scenario(name: "stash", file: "story.txt"),
    Scenario(name: "add-add", file: "added.txt"),
    Scenario(name: "whitespace", file: "code.txt"),
    Scenario(name: "crlf", file: "story.txt"),
    Scenario(name: "utf16", file: "greeting.txt"),
    Scenario(name: "many", file: "file-01.txt"),
    Scenario(name: "big", file: "big.txt"),
  ]

  var testDescription: String { name }

  /// Prepares the repository in a temporary folder and returns the merge with its context; the
  /// folder is removed before this returns.
  ///
  /// - Parameter options: How to compare; by default in the mode a window starts in.
  func load(
    options: ComparisonOptions = .init(mode: .windowDefault)
  ) async throws -> (Session, SessionContext) {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "SeamergeUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: folder.appending(path: "home"), withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let environment = Self.environment(home: folder.appending(path: "home"))
    let repository = folder.appending(path: name, directoryHint: .isDirectory)
    let made = try Self.run(
      Self.script, [repository.path, name], environment: environment, in: folder)
    try #require(made.status == 0, "make-test-repo.sh \(name): \(made.output)")

    let stages = try Self.run(
      Self.git, ["checkout-index", "--stage=all", "--temp", "--", file],
      environment: environment, in: repository)
    try #require(stages.status == 0, "checkout-index: \(stages.output)")
    let names = stages.output.split(separator: "\t").first.map {
      $0.split(separator: " ").map(String.init)
    }
    let temporary = try #require(names, "checkout-index printed \(stages.output)")
    try #require(temporary.count == 3, "checkout-index printed \(stages.output)")
    func source(_ index: Int) throws -> SourceFile? {
      guard temporary[index] != "." else { return nil }
      return SourceFile(
        bytes: try Data(contentsOf: repository.appending(path: temporary[index])), label: file)
    }
    let mergedFile = repository.appending(path: file)
    let git = GitContext.detect(
      workingDirectory: repository, mergedFile: mergedFile,
      git: Git(environment: environment, timeout: .seconds(10)))
    let session = try await Session.merge(
      base: git.hasCommonAncestor ? source(0) : nil, a: try #require(source(2)),
      b: try #require(source(1)), options: options)
    return (session, SessionContext(resultURL: mergedFile, git: git))
  }

  /// The environment without Git's variables, with the configuration of the user and the
  /// system out of reach.
  private static func environment(home: URL) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = home.path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    return environment
  }

  private static func run(
    _ executable: URL, _ arguments: [String], environment: [String: String], in directory: URL
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

  private static let git = Git().executableURL

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
