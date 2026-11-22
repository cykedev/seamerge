import Darwin
import Foundation
import GitSupport
import Testing

/// A run of `git difftool` in a repository of its own, whose tool hands each comparison to the
/// test and ends with the exit status the test gives it, as the helper ends with the outcome of
/// its window.
///
/// The tool is a script that writes what Git passes it into one named pipe and reads the exit
/// status from another, so that Git waits for the test exactly as it waits for the helper. Git
/// reads a configuration of its own and none of the user's.
@MainActor
final class DifftoolRun {
  /// What Git passed the tool for one comparison.
  struct Comparison {
    /// The folder Git started the tool in, the top of the working tree.
    var workingDirectory: URL

    /// The left and the right side, files or, with `--dir-diff`, folders, as absolute paths.
    var left: URL
    var right: URL

    /// The path of the compared file in the repository; empty with `--dir-diff`.
    var path: String
  }

  let folder: URL
  let repository: URL
  private let requests: URL
  private let replies: URL
  private let environment: [String: String]
  private var process: Process?
  private var finished: Task<Int32, Never>?
  private let output: URL

  /// A repository with `files` committed, each then changed in the working tree as `changed`
  /// says.
  init(committed files: [String: String], changed: [String: String]) throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "DifftoolRun-\(UUID().uuidString)", directoryHint: .isDirectory)
    repository = folder.appending(path: "repository", directoryHint: .isDirectory)
    requests = folder.appending(path: "requests")
    replies = folder.appending(path: "replies")
    output = folder.appending(path: "output.txt")
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    for pipe in [requests, replies] {
      try #require(mkfifo(pipe.path, 0o600) == 0, "mkfifo \(pipe.path)")
    }
    let script = folder.appending(path: "tool.sh")
    try Data(
      """
      #!/bin/sh
      printf '%s\\n%s\\n%s\\n%s\\n' "$PWD" "$1" "$2" "$3" > "\(requests.path)"
      read status < "\(replies.path)"
      exit "$status"

      """.utf8
    ).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let configuration = folder.appending(path: "gitconfig")
    try Data(
      """
      [user]
      \tname = Test
      \temail = test@example.com
      [init]
      \tdefaultBranch = main
      [diff]
      \ttool = probe
      [difftool]
      \tprompt = false
      \ttrustExitCode = true
      [difftool "probe"]
      \tcmd = '\(script.path)' \"$LOCAL\" \"$REMOTE\" \"$MERGED\"

      """.utf8
    ).write(to: configuration)
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = configuration.path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["HOME"] = folder.path
    self.environment = environment
    try git(["init", "-q"])
    for (path, text) in files {
      try write(text, to: path)
    }
    try git(["add", "."])
    try git(["commit", "-q", "-m", "First"])
    for (path, text) in changed {
      try write(text, to: path)
    }
  }

  isolated deinit {
    // A tool that still waits would keep Git running.
    let reply = open(replies.path, O_WRONLY | O_NONBLOCK)
    if reply >= 0 {
      _ = "1\n".withCString { Darwin.write(reply, $0, 2) }
      close(reply)
    }
    process?.terminate()
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record("Could not remove \(folder.path): \(error)")
    }
  }

  /// Writes `text` into the file at `path` of the working tree.
  func write(_ text: String, to path: String) throws {
    let url = repository.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  /// The text of the file at `path` of the working tree.
  func text(of path: String) throws -> String {
    try String(contentsOf: repository.appending(path: path), encoding: .utf8)
  }

  /// Runs `git` with `arguments` in the repository and returns its output.
  @discardableResult
  func git(_ arguments: [String]) throws -> String {
    let data = try Git(environment: environment).run(arguments, in: repository)
    return String(decoding: data, as: UTF8.self)
  }

  /// Starts `git difftool` with `arguments`, which waits for the test for each comparison.
  func start(_ arguments: [String] = []) throws {
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let process = Process()
    process.executableURL = Git(environment: environment).executableURL
    process.arguments = ["difftool"] + arguments
    process.currentDirectoryURL = repository
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let log = try FileHandle(forWritingTo: output)
    process.standardOutput = log
    process.standardError = log
    let ended = AsyncStream<Int32>.makeStream()
    process.terminationHandler = { process in
      ended.continuation.yield(process.terminationStatus)
      ended.continuation.finish()
    }
    try process.run()
    self.process = process
    finished = Task {
      for await status in ended.stream {
        return status
      }
      return -1
    }
  }

  /// The next comparison Git hands the tool, once it does.
  func nextComparison() async throws -> Comparison {
    let path = requests.path
    let text = await Task.detached {
      // Opening the pipe waits until the tool opens it to write.
      let handle = FileHandle(forReadingAtPath: path)
      return handle.map { String(decoding: $0.readDataToEndOfFile(), as: UTF8.self) }
    }.value
    let lines = try #require(text?.components(separatedBy: "\n"))
    try #require(lines.count >= 4, "The tool wrote \(lines)")
    // Git passes the working copy by its path from the folder it starts the tool in.
    let workingDirectory = URL(filePath: lines[0], directoryHint: .isDirectory)
    let side = { (path: String) in URL(filePath: path, relativeTo: workingDirectory).absoluteURL }
    return Comparison(
      workingDirectory: workingDirectory, left: side(lines[1]), right: side(lines[2]),
      path: lines[3])
  }

  /// Ends the comparison Git waits for with `status`, as the helper ends with the outcome of its
  /// window: 0 for saved, 1 for cancelled.
  func reply(_ status: Int32) async {
    let path = replies.path
    await Task.detached {
      // Opening the pipe waits until the tool opens it to read.
      guard let handle = FileHandle(forWritingAtPath: path) else {
        Issue.record("Cannot open \(path)")
        return
      }
      do {
        try handle.write(contentsOf: Data("\(status)\n".utf8))
        try handle.close()
      } catch {
        Issue.record("Cannot reply to the tool: \(error)")
      }
    }.value
  }

  /// Waits until `git difftool` ends and returns its exit status and what it wrote.
  func finish() async throws -> (status: Int32, output: String) {
    let status = await finished?.value ?? -1
    return (status, try String(contentsOf: output, encoding: .utf8))
  }
}
