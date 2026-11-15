import Foundation
import Testing

/// A throwaway repository in a temporary folder, in which a patch is tried with `git apply` and
/// `patch`, with the configuration of the user and the system out of reach.
struct PatchTrial {
  /// The exit status of a run and what it printed, standard error after standard output.
  struct Outcome {
    let status: Int32
    let output: String
  }

  /// The top of the working tree.
  let directory: URL

  /// The folder that holds the working tree, the patch and the empty configuration, and stands
  /// in for the home folder.
  private let folder: URL

  /// Creates a repository whose working tree holds `files`, by path; ``remove()`` takes it away.
  init(files: [String: Data]) throws {
    folder = FileManager.default.temporaryDirectory
      .appending(path: "MergeModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    directory = folder.appending(path: "repository", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.write(files, into: directory)
    let initialized = try git(["init", "--quiet"])
    try #require(initialized.status == 0, "git init: \(initialized.output)")
  }

  /// Removes the repository and its folder.
  func remove() {
    #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) }
  }

  /// Runs Git in the working tree with `arguments`.
  func git(_ arguments: [String]) throws -> Outcome {
    let executable = try #require(Git.executable, "Git is not installed")
    return try run(executable, arguments)
  }

  /// Runs `patch` in the working tree with `arguments`, followed by the file of `patch`, in
  /// batch mode, which asks nothing.
  func patch(_ arguments: [String], with patch: Data) throws -> Outcome {
    try run(URL(filePath: "/usr/bin/patch"), ["--batch"] + arguments + ["-i", write(patch).path])
  }

  /// Runs `git apply` in the working tree with `arguments`, followed by the file of `patch`.
  func gitApply(_ arguments: [String], _ patch: Data) throws -> Outcome {
    try git(["apply"] + arguments + [write(patch).path])
  }

  /// Replaces the working tree with `files`, by path, leaving the repository as it is.
  func replaceFiles(with files: [String: Data]) throws {
    for path in try workingTreePaths() {
      try FileManager.default.removeItem(at: directory.appending(path: path))
    }
    try Self.write(files, into: directory)
  }

  /// The files of the working tree, by path, without the repository itself.
  func files() throws -> [String: Data] {
    try workingTreePaths().reduce(into: [:]) { files, path in
      files[path] = try Data(contentsOf: directory.appending(path: path))
    }
  }

  /// The paths of the regular files of the working tree, relative to its top.
  private func workingTreePaths() throws -> [String] {
    try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { path in
      var isDirectory: ObjCBool = false
      return path != ".git" && !path.hasPrefix(".git/")
        && FileManager.default.fileExists(
          atPath: directory.appending(path: path).path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
    }
  }

  private static func write(_ files: [String: Data], into directory: URL) throws {
    for (path, bytes) in files {
      let url = directory.appending(path: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
  }

  /// Writes `patch` into a file of its own beside the working tree.
  private func write(_ patch: Data) throws -> URL {
    let url = folder.appending(path: "change-\(UUID().uuidString).patch")
    try patch.write(to: url)
    return url
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

  /// Runs an executable in the working tree to its end.
  ///
  /// The standard error goes into a file, which never fills as a pipe does while the standard
  /// output is read.
  private func run(_ executable: URL, _ arguments: [String]) throws -> Outcome {
    let errorFile = folder.appending(path: "stderr-\(UUID().uuidString)")
    try #require(FileManager.default.createFile(atPath: errorFile.path, contents: nil))
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: errorFile) } }
    let error = try FileHandle(forWritingTo: errorFile)
    defer { #expect(throws: Never.self) { try error.close() } }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = directory
    let output = Pipe()
    // Without a terminal to read from, a tool that would ask, as `patch` asks for a file it
    // cannot find, reads the end of its input and fails rather than waits.
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let printed = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let complaint = try Data(contentsOf: errorFile)
    return Outcome(
      status: process.terminationStatus,
      output: String(decoding: printed + complaint, as: UTF8.self))
  }
}
