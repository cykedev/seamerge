import Foundation
import GitSupport
import Testing

struct GitTests {
  @Test func argumentsReachTheProcessUnchanged() throws {
    try withSandbox { sandbox in
      let bin = try sandbox.makeExecutable("git", script: #"printf '%s\n' "$@""#)
        .deletingLastPathComponent()
      let git = Git(environment: sandbox.environment.merging(["PATH": bin.path]) { $1 })
      let arguments = ["$HOME", "a b", "it's", #""quoted""#, "; exit 3", "`id`", "*"]

      let output = try git.run(arguments)

      #expect(String(decoding: output, as: UTF8.self) == arguments.joined(separator: "\n") + "\n")
    }
  }

  @Test func commandRunsInTheGivenDirectory() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")

      let output = try sandbox.git().run(["rev-parse", "--show-toplevel"], in: repository)

      let top = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .newlines)
      #expect(
        URL(filePath: top).resolvingSymlinksInPath().path
          == repository.resolvingSymlinksInPath().path)
    }
  }

  @Test func failureReportsTheStatusAndTheMessage() throws {
    try withSandbox { sandbox in
      #expect {
        try sandbox.git().run(["rev-parse", "--absolute-git-dir"], in: sandbox.directory)
      } throws: { error in
        guard case .failed(let arguments, let status, let message) = error as? GitError else {
          return false
        }
        return arguments == ["rev-parse", "--absolute-git-dir"] && status == 128
          && !message.isEmpty && !message.hasSuffix("\n")
      }
    }
  }

  @Test func outputLargerThanAPipeIsReadCompletely() throws {
    try withSandbox { sandbox in
      let bin = try sandbox.makeExecutable("git", script: "exec /usr/bin/head -c 1000000 /dev/zero")
        .deletingLastPathComponent()
      let git = Git(environment: sandbox.environment.merging(["PATH": bin.path]) { $1 })

      #expect(try git.run([]).count == 1_000_000)
    }
  }

  @Test func commandThatExceedsTheTimeLimitIsStopped() throws {
    try withSandbox { sandbox in
      let bin = try sandbox.makeExecutable("git", script: "exec /bin/sleep 30")
        .deletingLastPathComponent()
      let environment = sandbox.environment.merging(["PATH": bin.path]) { $1 }
      let git = Git(environment: environment, timeout: .milliseconds(200))
      let start = ContinuousClock.now

      #expect(throws: GitError.timedOut(arguments: ["status"])) { try git.run(["status"]) }
      #expect(ContinuousClock.now - start < .seconds(5))
    }
  }

  @Test func commandThatIgnoresTerminationIsKilled() throws {
    try withSandbox { sandbox in
      let pidFile = sandbox.directory.appending(path: "pid")
      let bin = try sandbox.makeExecutable(
        "git", script: "echo $$ > '\(pidFile.path)'; trap '' TERM; exec /bin/sleep 30"
      ).deletingLastPathComponent()
      let environment = sandbox.environment.merging(["PATH": bin.path]) { $1 }
      let git = Git(environment: environment, timeout: .milliseconds(200))
      let start = ContinuousClock.now

      #expect(throws: GitError.timedOut(arguments: ["status"])) { try git.run(["status"]) }

      #expect(ContinuousClock.now - start < .seconds(5))
      let pidText = try String(contentsOf: pidFile, encoding: .utf8)
      let pid = try #require(Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
      #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
  }

  @Test func firstGitOnTheSearchPathRuns() throws {
    try withSandbox { sandbox in
      let empty = sandbox.directory.appending(path: "empty", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
      let first = try sandbox.makeExecutable("git", in: "first", script: "echo first")
      _ = try sandbox.makeExecutable("git", in: "second", script: "echo second")
      let second = sandbox.directory.appending(path: "second")
      let searchPath = [empty.path, first.deletingLastPathComponent().path, second.path]

      let git = Git(environment: ["PATH": searchPath.joined(separator: ":")])

      #expect(git.executableURL == first)
    }
  }

  @Test func withoutGitOnTheSearchPathTheSystemGitRuns() {
    #expect(
      Git(environment: ["PATH": "/nonexistent"]).executableURL == URL(filePath: "/usr/bin/git"))
    #expect(Git(environment: [:]).executableURL == URL(filePath: "/usr/bin/git"))
  }
}
