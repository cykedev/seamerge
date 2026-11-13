import Foundation
import SeamergeCLI
import SessionIPC
import Testing

@Suite("Arguments", .timeLimit(.minutes(1)))
struct ArgumentTests {
  @Test(arguments: [
    ["--help"], ["merge", "--help"], ["diff", "--label-left", "x", "--help"],
    ["merge", "--lokal", "--help"], ["a", "b", "c", "--version", "--help"],
  ])
  func helpIsPrintedOnStandardOutput(arguments: [String]) async throws {
    try await withSandbox { sandbox in
      let result = await sandbox.run(arguments)
      #expect(result.exitStatus == 0)
      #expect(result.errorOutput.isEmpty)
      #expect(result.output.hasPrefix("Usage:\n  seamerge merge "))
      for option in [
        "--base", "--local", "--remote", "--output", "--label-base", "--label-local",
        "--label-remote", "--from-git", "--path", "--label-left", "--label-right", "--version",
      ] {
        #expect(result.output.contains(option), "\(option) is not in the help")
      }
      let longestLine = result.output.split(separator: "\n").map(\.count).max() ?? 0
      #expect(longestLine <= 80)
    }
  }

  @Test func versionIsPrintedOnStandardOutput() async throws {
    try await withSandbox { sandbox in
      let result = await sandbox.run(["--version"])
      #expect(result == CommandResult(exitStatus: 0, output: "seamerge 1.2.3\n"))
    }
  }

  @Test(arguments: [
    ([], "Name two files to compare. See 'seamerge --help'."),
    (["merge", "--local"], "Add a value after --local. See 'seamerge --help'."),
    (["merge", "--lokal", "a"], "Unknown option '--lokal'. See 'seamerge --help'."),
    (
      ["diff", "--base", "a", "b", "c"],
      "Unknown option '--base'. Put '--' before a file whose name starts with '-', "
        + "or see 'seamerge --help'."
    ),
    (
      ["-x.txt", "y.txt"],
      "Unknown option '-x.txt'. Put '--' before a file whose name starts with '-', "
        + "or see 'seamerge --help'."
    ),
    (["merge", "--path", "a"], "Unknown option '--path'. See 'seamerge --help'."),
    (
      ["merge", "--local", "a", "--local", "b", "--remote", "c", "--output", "d"],
      "Give --local only once."
    ),
    (
      ["merge", "--local", "a", "--remote", "b"],
      "Add --output <file> to the merge. See 'seamerge --help'."
    ),
    (
      ["merge", "--local", "a", "--remote", "b", "--output", "c", "d"],
      "Unexpected argument 'd'. See 'seamerge --help'."
    ),
    (["diff"], "Name two files to compare. See 'seamerge --help'."),
    (["old.txt"], "Name a second file to compare. See 'seamerge --help'."),
    (["a", "b", "c"], "Unexpected argument 'c'. See 'seamerge --help'."),
  ])
  func invalidInvocationEndsWithTwoAndSaysWhatToDo(
    arguments: [String], message: String
  ) async throws {
    try await withSandbox { sandbox in
      let result = await sandbox.run(arguments)
      #expect(result == CommandResult(exitStatus: 2, errorOutput: "seamerge: \(message)\n"))
    }
  }

  @Test func fileThatDoesNotExistEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("old.txt")
      let result = await sandbox.run(["old.txt", "new.txt"])
      let path = sandbox.directory.appending(path: "new.txt").path
      #expect(result.exitStatus == 2)
      #expect(result.errorOutput == "seamerge: Cannot find '\(path)'. Check the path.\n")
    }
  }

  @Test func folderInPlaceOfAFileEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("old.txt")
      let result = await sandbox.run(["old.txt", "home"])
      let path = sandbox.directory.appending(path: "home").path
      #expect(result.exitStatus == 2)
      #expect(result.errorOutput == "seamerge: '\(path)' is a folder. Name a file instead.\n")
    }
  }

  @Test func unreadableFileEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("old.txt")
      let locked = try sandbox.makeFile("locked.txt")
      try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: locked.path)
      let result = await sandbox.run(["old.txt", "locked.txt"])
      #expect(result.exitStatus == 2)
      #expect(
        result.errorOutput == "seamerge: Cannot read '\(locked.path)'. Check its permissions.\n")
    }
  }

  @Test func emptyFileNameEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let merge = await sandbox.run([
        "merge", "--local", "", "--remote", "a.txt", "--output", "a.txt",
      ])
      #expect(merge.exitStatus == 2)
      #expect(merge.errorOutput == "seamerge: The file name after --local is empty. Name a file.\n")
      let diff = await sandbox.run(["a.txt", ""])
      #expect(diff.exitStatus == 2)
      #expect(diff.errorOutput == "seamerge: A file name is empty. Name a file.\n")
    }
  }

  @Test func outputInAFolderThatDoesNotExistEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let result = await sandbox.run([
        "merge", "--local", "a.txt", "--remote", "a.txt", "--output", "missing/result.txt",
      ])
      let path = sandbox.directory.appending(path: "missing/result.txt").path
      #expect(result.exitStatus == 2)
      #expect(
        result.errorOutput
          == "seamerge: Cannot find the folder to save '\(path)' in. Check the path.\n")
    }
  }

  @Test func filesAreSentWithAbsolutePaths() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      let folder = sandbox.directory.appending(path: "work", directoryHint: .isDirectory)
      try sandbox.makeFile("work/local.txt")
      try sandbox.makeFile("remote.txt")
      try sandbox.makeFile("base.txt")
      let result = await sandbox.run(
        [
          "merge", "--base", "../base.txt", "--local", "./local.txt", "--remote",
          sandbox.directory.appending(path: "remote.txt").path, "--output", "result.txt",
        ], in: folder)
      #expect(result.exitStatus == 0)
      let request = try await app.nextRequest()
      let merge = try #require(request.merge)
      #expect(merge.base?.path == sandbox.directory.appending(path: "base.txt").path)
      #expect(merge.local.path == folder.appending(path: "local.txt").path)
      #expect(merge.remote.path == sandbox.directory.appending(path: "remote.txt").path)
      #expect(merge.output.path == folder.appending(path: "result.txt").path)
      await app.stop()
    }
  }

  @Test func pathsWithSpacesAndSpecialCharactersArriveUnchanged() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      let names = [#"a b 'c' "d" $HOME #1 %20 ?.txt"#, "-dash; ü\u{301} 😀 \\ *.txt"]
      for name in names { try sandbox.makeFile("folder: [x]/\(name)") }
      let result = await sandbox.run(
        ["diff", "--path", "folder: [x]/\(names[0])", "--"] + names.map { "folder: [x]/\($0)" })
      #expect(result.exitStatus == 0)
      let diff = try #require(try await app.nextRequest().diff)
      let folder = sandbox.directory.appending(path: "folder: [x]").path
      #expect(diff.left.path(percentEncoded: false) == "\(folder)/\(names[0])")
      #expect(diff.right.path(percentEncoded: false) == "\(folder)/\(names[1])")
      #expect(diff.displayPath == "folder: [x]/\(names[0])")
      await app.stop()
    }
  }

  @Test func optionValuesMayStartWithADash() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("-old.txt")
      try sandbox.makeFile("new.txt")
      let result = await sandbox.run([
        "--label-left", "--label-right", "--label-right", "-", "--", "-old.txt", "new.txt",
      ])
      #expect(result.exitStatus == 0)
      let diff = try #require(try await app.nextRequest().diff)
      #expect(diff.leftLabel == "--label-right")
      #expect(diff.rightLabel == "-")

      let helpAndVersion = await sandbox.run([
        "diff", "--label-left", "--help", "--label-right", "--version", "--", "-old.txt", "new.txt",
      ])
      #expect(helpAndVersion.exitStatus == 0)
      #expect(helpAndVersion.output.isEmpty)
      let labelled = try #require(try await app.nextRequest().diff)
      #expect(labelled.leftLabel == "--help")
      #expect(labelled.rightLabel == "--version")
      #expect(diff.left.lastPathComponent == "-old.txt")
      await app.stop()
    }
  }

  @Test func shortFormIsADiff() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("old.txt")
      try sandbox.makeFile("new.txt")
      #expect(await sandbox.run(["old.txt", "new.txt"]).exitStatus == 0)
      #expect(await sandbox.run(["diff", "old.txt", "new.txt"]).exitStatus == 0)
      let short = try await app.nextRequest()
      let long = try await app.nextRequest()
      #expect(short == long)
      let diff = try #require(short.diff)
      #expect(diff.left.lastPathComponent == "old.txt")
      #expect(diff.right.lastPathComponent == "new.txt")
      #expect(diff.displayPath == nil)
      #expect(diff.context == SessionRequest.DiffContext())
      await app.stop()
    }
  }

  @Test(arguments: [nil, "", "missing-base.txt"])
  func missingBaseLeadsToAMergeWithoutBase(base: String?) async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("a.txt")
      let baseArguments = base.map { ["--base", $0] } ?? []
      let result = await sandbox.run(
        ["merge"] + baseArguments + ["--local", "a.txt", "--remote", "a.txt", "--output", "a.txt"])
      #expect(result.exitStatus == 0)
      let merge = try #require(try await app.nextRequest().merge)
      #expect(merge.base == nil)
      await app.stop()
    }
  }

  @Test func baseThatCannotBeReadEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let result = await sandbox.run([
        "merge", "--base", "home", "--local", "a.txt", "--remote", "a.txt", "--output", "a.txt",
      ])
      #expect(result.exitStatus == 2)
      #expect(result.errorOutput.hasSuffix("/home' is a folder. Name a file instead.\n"))
    }
  }

  @Test func onlyAMergeWithFromGitSaysThatGitWaits() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("a.txt")
      let files = ["--local", "a.txt", "--remote", "a.txt", "--output", "a.txt"]

      #expect(await sandbox.run(["merge"] + files).exitStatus == 0)
      #expect(try await app.nextRequest().merge?.isRunByGit == false)
      #expect(await sandbox.run(["merge", "--from-git"] + files).exitStatus == 0)
      #expect(try await app.nextRequest().merge?.isRunByGit == true)
      await app.stop()

      let twice = await sandbox.run(["merge", "--from-git", "--from-git"] + files)
      #expect(
        twice == CommandResult(exitStatus: 2, errorOutput: "seamerge: Give --from-git only once.\n")
      )
    }
  }

  @Test func labelsNameTheSides() async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      try sandbox.makeFile("a.txt")
      let merge = await sandbox.run([
        "merge", "--base", "a.txt", "--local", "a.txt", "--remote", "a.txt", "--output", "a.txt",
        "--label-base", "Base label", "--label-local", "Local label", "--label-remote", "Remote",
      ])
      #expect(merge.exitStatus == 0)
      let context = try #require(try await app.nextRequest().merge).context
      #expect(context.base.name == .reference("Base label"))
      #expect(context.local.name == .reference("Local label"))
      #expect(context.remote.name == .reference("Remote"))

      let diff = await sandbox.run([
        "diff", "--label-left", "Left label", "--label-right", "Right label", "a.txt", "a.txt",
      ])
      #expect(diff.exitStatus == 0)
      let request = try #require(try await app.nextRequest().diff)
      #expect(request.leftLabel == "Left label")
      #expect(request.rightLabel == "Right label")
      await app.stop()
    }
  }
}

extension SessionRequest {
  /// The merge, if this is one.
  var merge: Merge? {
    guard case .merge(let merge) = self else { return nil }
    return merge
  }

  /// The comparison, if this is one.
  var diff: Diff? {
    guard case .diff(let diff) = self else { return nil }
    return diff
  }
}
