import Foundation
import Testing

/// Applies patches in throwaway repositories in temporary folders, with the configuration of
/// the user and the system out of reach.
enum PatchApplication {
  /// The tools that apply a patch.
  enum Tool {
    /// `git apply`.
    case git

    /// `patch -p1` in batch mode, which removes the files that it empties.
    case patch
  }

  /// The files, by path, of a working tree that held `files` after `tool` applied `patch`.
  @concurrent
  static func apply(_ patch: Data, to files: [String: Data], with tool: Tool) async throws
    -> [String: Data]
  {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SeamergePatches-\(UUID().uuidString)", directoryHint: .isDirectory)
    let tree = folder.appending(path: "repository", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    for (path, bytes) in files {
      let url = tree.appending(path: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
    let patchFile = folder.appending(path: "change.patch")
    try patch.write(to: patchFile)
    let git = try #require(
      ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        .map { URL(filePath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }, "Git is not installed")
    let initialized = try run(git, ["init", "--quiet"], in: tree, home: folder)
    try #require(initialized.status == 0, "git init: \(initialized.output)")
    let applied =
      switch tool {
      case .git: try run(git, ["apply", patchFile.path], in: tree, home: folder)
      case .patch:
        try run(
          URL(filePath: "/usr/bin/patch"), ["--batch", "-p1", "-E", "-i", patchFile.path], in: tree,
          home: folder)
      }
    try #require(applied.status == 0, "\(tool): \(applied.output)")
    let paths = try FileManager.default.subpathsOfDirectory(atPath: tree.path).filter { path in
      var isDirectory: ObjCBool = false
      return path != ".git" && !path.hasPrefix(".git/")
        && FileManager.default.fileExists(
          atPath: tree.appending(path: path).path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
    }
    return try paths.reduce(into: [:]) { result, path in
      result[path] = try Data(contentsOf: tree.appending(path: path))
    }
  }

  /// Runs an executable in `directory` to its end and returns its exit status and what it
  /// printed; standard error goes into a file, which never fills as a pipe can.
  private static func run(
    _ executable: URL, _ arguments: [String], in directory: URL, home: URL
  ) throws -> (status: Int32, output: String) {
    let errorFile = home.appending(path: "stderr-\(UUID().uuidString)")
    try #require(FileManager.default.createFile(atPath: errorFile.path, contents: nil))
    let error = try FileHandle(forWritingTo: errorFile)
    defer { #expect(throws: Never.self) { try error.close() } }
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = home.path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
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
    return (process.terminationStatus, String(decoding: printed + complaint, as: UTF8.self))
  }
}
