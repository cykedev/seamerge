import Foundation
import Testing

/// Runs Git on files in a temporary folder, with an empty configuration of its own.
enum Git {
  /// The output and exit status of a run.
  struct Outcome {
    let output: String
    let status: Int32
  }

  /// The Git executable, or `nil` if Git is not installed.
  static let executable: URL? = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
    .map(URL.init(fileURLWithPath:))
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }

  /// Writes `files` into a temporary folder and runs Git there with `arguments`.
  static func run(_ arguments: [String], files: [String: String]) throws -> Outcome {
    let executable = try #require(executable, "Git is not installed")
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "MergeModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
    let configuration = directory.appending(path: "gitconfig")
    try Data().write(to: configuration)
    for (name, content) in files {
      try Data(content.utf8).write(to: directory.appending(path: name))
    }

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = ["GIT_CONFIG_GLOBAL": configuration.path, "GIT_CONFIG_NOSYSTEM": "1"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Outcome(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
  }
}
