import Foundation
import GitSupport
import SeamergeCLI
import SessionIPC
import Testing

/// `seamerge diff --collect`: the origin goes with a comparison that may join others, the
/// command ends once the app has the files, and two folders are a directory diff.
@Suite(.timeLimit(.minutes(1)))
struct CollectTests {
  @Test func collectedComparisonEndsWithSuccessOnceTheAppHasTheFiles() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .accept)
      try sandbox.makeFile("old.txt")
      try sandbox.makeFile("new.txt")
      var environment = sandbox.environment
      environment["GIT_DIFF_PATH_COUNTER"] = "2"
      environment["GIT_DIFF_PATH_TOTAL"] = "3"

      let result = await sandbox.command().run(
        ["diff", "--collect", "--path", "new.txt", "old.txt", "new.txt"],
        standardInput: StandardInput(.nullDevice), workingDirectory: sandbox.directory,
        environment: environment)

      #expect(result.exitStatus == 0, "\(result)")
      let diff = try #require(try await app.nextRequest().diff)
      let origin = try #require(diff.origin)
      #expect(
        origin.repository == sandbox.directory.standardizedFileURL.path(percentEncoded: false))
      #expect(
        origin.run
          == ProcessRun.difftoolRun().map {
            SessionRequest.Run(processID: $0.processID, startTime: $0.startTime)
          })
      #expect(diff.context.filePosition == SessionRequest.FilePosition(number: 2, count: 3))
      await app.stop()
    }
  }

  /// A run of one file, and calls that Git does not number, as from a shell that runs many.
  @Test(arguments: [
    (["diff", "old.txt", "new.txt"], "3"), (["diff", "--collect", "old.txt", "new.txt"], "1"),
    (["diff", "--collect", "old.txt", "new.txt"], nil),
  ])
  func comparisonThatCannotJoinOthersWaitsAsBefore(arguments: [String], total: String?)
    async throws
  {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))
      try sandbox.makeFile("old.txt")
      try sandbox.makeFile("new.txt")
      var environment = sandbox.environment
      if let total {
        environment["GIT_DIFF_PATH_COUNTER"] = "1"
        environment["GIT_DIFF_PATH_TOTAL"] = total
      }

      let result = await sandbox.command().run(
        arguments, standardInput: StandardInput(.nullDevice), workingDirectory: sandbox.directory,
        environment: environment)

      #expect(result.exitStatus == 1)
      #expect(try #require(try await app.nextRequest().diff).origin == nil)
      await app.stop()
    }
  }

  /// Git passes the folders of its directory diff with `--collect` and an empty path, Tower
  /// with `--collect` alone, a setup made before `--collect` with `--path`; two folders named
  /// without either are the user's.
  @Test(arguments: [
    (["diff", "--collect", "--path", "", "--", "left", "right"], true),
    (["diff", "--collect", "--", "left", "right"], true),
    (["diff", "--path", "", "--", "left", "right"], true),
    (["diff", "--", "left", "right"], false), (["left", "right"], false),
  ])
  func twoFoldersAreADirectoryDiff(arguments: [String], isFromGit: Bool) async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("left/a.txt")
      try sandbox.makeFile("right/a.txt")

      let result = await sandbox.run(arguments)

      #expect(result.exitStatus == 0, "\(result)")
      guard case .folders(let folders) = try await app.nextRequest() else {
        Issue.record("The folders were not sent as a directory diff")
        return
      }
      #expect(folders.left.lastPathComponent == "left")
      #expect(folders.right.lastPathComponent == "right")
      #expect(folders.isFromGit == isFromGit)
      await app.stop()
    }
  }

  @Test func folderBesideAFileEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("left/a.txt")
      try sandbox.makeFile("a.txt")

      let result = await sandbox.run(["diff", "--collect", "left", "a.txt"])

      #expect(result.exitStatus == 2)
    }
  }

  @Test func runOfTheToolIsTheClosestProcessThatIsNotAShell() throws {
    let shell = Process()
    shell.executableURL = URL(filePath: "/bin/sh")
    let pipe = Pipe()
    shell.standardInput = pipe
    try shell.run()
    defer {
      shell.terminate()
      shell.waitUntilExit()
    }

    let run = try #require(ProcessRun.difftoolRun(above: shell.processIdentifier))

    #expect(run.processID == getpid())
    #expect(run.isRunning)
    #expect(ProcessRun(processID: run.processID, startTime: run.startTime - 1).isRunning == false)
  }
}
