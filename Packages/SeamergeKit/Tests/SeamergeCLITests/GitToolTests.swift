import Foundation
import GitSupport
import SeamergeCLI
import SessionIPC
import Testing

/// Runs `git mergetool` and `git difftool` with the configuration the app writes, against an app in
/// the test.
@Suite("Git tools", .timeLimit(.minutes(1)))
struct GitToolTests {
  @Test func savedMergeStagesTheFile() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge", in: "repo with spaces, 'quotes' & $x")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .save("resolved\n"))

      let (gitResult, result) = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        try await tool.runNextInvocation(of: sandbox.command())
      }

      #expect(result == CommandResult(exitStatus: 0))
      #expect(gitResult.status == 0, "\(gitResult.output)")
      let merged = repository.appending(path: "story.txt")
      #expect(try String(contentsOf: merged, encoding: .utf8) == "resolved\n")
      #expect(try sandbox.git.output(["ls-files", "--unmerged"], in: repository).isEmpty)
      #expect(
        try sandbox.git.output(["diff", "--cached", "--name-only"], in: repository) == "story.txt")

      let merge = try #require(try await app.nextRequest().merge)
      #expect(merge.output.path(percentEncoded: false) == merged.path(percentEncoded: false))
      #expect(merge.base != nil)
      #expect(merge.isRunByGit)
      #expect(merge.context.operation == .merge)
      #expect(merge.context.remote.name == .reference("feature"))
      #expect(merge.context.remote.role == .incoming)
      #expect(merge.context.local.name == .reference("main"))
      #expect(merge.context.local.role == .yours)
      #expect(merge.context.remainingConflictedFileCount == 0)
      await app.stop()
    }
  }

  @Test func cancelledMergeFailsAndLeavesTheFileAsItWas() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let tool = try sandbox.configureTool()
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))
      let merged = repository.appending(path: "story.txt")
      let before = try Data(contentsOf: merged)

      let (gitResult, result) = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        try await tool.runNextInvocation(of: sandbox.command())
      }

      #expect(result == CommandResult(exitStatus: 1))
      #expect(gitResult.status != 0)
      #expect(gitResult.output.contains("merge of story.txt failed"), "\(gitResult.output)")
      #expect(try Data(contentsOf: merged) == before)
      #expect(!(try sandbox.git.output(["ls-files", "--unmerged"], in: repository).isEmpty))
      await app.stop()
    }
  }

  @Test func appThatCannotBeReachedFailsTheMergeWithItsMessage() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let tool = try sandbox.configureTool()

      let (gitResult, result) = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        try await tool.runNextInvocation(of: sandbox.command(connectionTimeout: .milliseconds(300)))
      }

      #expect(result.exitStatus == 3)
      #expect(gitResult.status != 0)
      #expect(gitResult.output.contains(result.errorOutput), "\(gitResult.output)")
      #expect(gitResult.output.contains("merge of story.txt failed"))
    }
  }

  @Test func rebaseProgressReachesTheApp() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))

      _ = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        try await tool.runNextInvocation(of: sandbox.command())
      }

      let context = try #require(try await app.nextRequest().merge).context
      #expect(context.operation == .rebase)
      #expect(context.remote.role == .yourCommit)
      #expect(context.local.role == .rebaseTarget)
      let commit = try #require(context.remote.commit)
      #expect(commit.subject.isEmpty == false)
      #expect(commit.hash.count == 40 && commit.hash.hasPrefix(commit.abbreviatedHash))
      let progress = try #require(context.rebaseProgress)
      #expect(progress.targetName == .reference("main"))
      #expect(progress.commitNumber == 2)
      #expect(progress.commitCount == 3)
      await app.stop()
    }
  }

  @Test func otherConflictedFilesAreCounted() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("many")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))

      _ = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        try await tool.runNextInvocation(of: sandbox.command())
      }

      let context = try #require(try await app.nextRequest().merge).context
      #expect(context.remainingConflictedFileCount == 11)
      await app.stop()
    }
  }

  @Test func fileBothSidesAddedIsMergedWithoutABase() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("add-add")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))

      _ = try await runGit(["mergetool"], in: repository, sandbox: sandbox) {
        let invocation = try await tool.nextInvocation()
        let baseIndex = try #require(invocation.arguments.firstIndex(of: "--base"))
        let baseFile = invocation.workingDirectory.appending(
          path: invocation.arguments[baseIndex + 1])
        #expect(try Data(contentsOf: baseFile).isEmpty, "Git hands over an empty base")
        try tool.finish(
          with: await sandbox.command().run(
            invocation.arguments, workingDirectory: invocation.workingDirectory,
            environment: invocation.environment))
      }

      let merge = try #require(try await app.nextRequest().merge)
      #expect(merge.base == nil)
      #expect(merge.context.base == SessionRequest.Side())
      await app.stop()
    }
  }

  @Test func closedComparisonMovesOnToTheNextFile() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))

      let (gitResult, _) = try await runGit(["difftool"], in: repository, sandbox: sandbox) {
        () async throws in
        for _ in 0..<3 {
          #expect(try await tool.runNextInvocation(of: sandbox.command()).exitStatus == 0)
        }
      }

      #expect(gitResult.status == 0, "\(gitResult.output)")
      var compared: [String] = []
      for number in 1...3 {
        let diff = try #require(try await app.nextRequest().diff)
        let path = try #require(diff.displayPath)
        compared.append(path)
        #expect(diff.context.filePosition == SessionRequest.FilePosition(number: number, count: 3))
        #expect(diff.context.leftRole == .before)
        #expect(diff.context.rightRole == .workingCopy)
        #expect(
          diff.right.path(percentEncoded: false)
            == repository.appending(path: path).path(percentEncoded: false))
      }
      #expect(compared == ["one.txt", "three.txt", "two.txt"])
      await app.stop()
    }
  }

  @Test func failedComparisonEndsTheRun() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let tool = try sandbox.configureTool()
      let app = try ScriptedApp(at: sandbox.socketURL) { request in
        request.diff?.context.filePosition?.number == 2 ? .close(.cancelled) : .close(.saved)
      }

      // Git ends without a third call; a third one would wait until the time limit.
      let (gitResult, _) = try await runGit(["difftool"], in: repository, sandbox: sandbox) {
        () async throws in
        #expect(try await tool.runNextInvocation(of: sandbox.command()).exitStatus == 0)
        #expect(try await tool.runNextInvocation(of: sandbox.command()).exitStatus == 1)
      }

      #expect(gitResult.status != 0, "\(gitResult.output)")
      await app.stop()
    }
  }

  @Test func fileWhoseNameStartsWithADashIsCompared() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let file = repository.appending(path: "-x.txt")
      try Data("first\n".utf8).write(to: file)
      _ = try sandbox.git.run(["add", "--", "-x.txt"], in: repository)
      _ = try sandbox.git.run(["commit", "--quiet", "--message", "Add -x.txt"], in: repository)
      try Data("second\n".utf8).write(to: file)
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))

      let (gitResult, result) = try await runGit(
        ["difftool", "--", "-x.txt"], in: repository, sandbox: sandbox
      ) {
        try await tool.runNextInvocation(of: sandbox.command())
      }

      #expect(result == CommandResult(exitStatus: 0))
      #expect(gitResult.status == 0, "\(gitResult.output)")
      let diff = try #require(try await app.nextRequest().diff)
      #expect(diff.displayPath == "-x.txt")
      #expect(diff.right.path(percentEncoded: false) == file.path(percentEncoded: false))
      #expect(diff.context.rightRole == .workingCopy)
      await app.stop()
    }
  }

  @Test func addedAndDeletedFilesArePassedAsEmptySides() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff-new")
      let tool = try sandbox.configureTool()
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))

      let (gitResult, _) = try await runGit(["difftool"], in: repository, sandbox: sandbox) {
        () async throws in
        for _ in 0..<2 {
          #expect(try await tool.runNextInvocation(of: sandbox.command()).exitStatus == 0)
        }
      }

      #expect(gitResult.status == 0, "\(gitResult.output)")
      let emptySide = URL(filePath: "/dev/null")
      let added = try #require(try await app.nextRequest().diff)
      #expect(added.displayPath == "added.txt")
      #expect(added.left == emptySide)
      #expect(added.right.lastPathComponent == "added.txt")
      let removed = try #require(try await app.nextRequest().diff)
      #expect(removed.displayPath == "removed.txt")
      #expect(removed.left != emptySide)
      #expect(removed.right == emptySide)
      await app.stop()
    }
  }

  @Test func cancelledWaitEndsGitAndTheScriptItStarted() async throws {
    try await withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let tool = try sandbox.configureTool()
      let (scripts, scriptSink) = AsyncStream.makeStream(of: pid_t.self)

      // The script waits for its answer, so a second invocation never comes: the test hangs as
      // one does that fails between starting Git and answering it, until its time limit cancels it.
      let hangingTest = Task {
        try await runGit(["difftool"], in: repository, sandbox: sandbox) {
          scriptSink.yield(try await tool.nextInvocation().processID)
          _ = try await tool.nextInvocation()
        }
      }
      var startedScripts = scripts.makeAsyncIterator()
      let script = try #require(await startedScripts.next())
      #expect(tool.hasWaitingScript)
      hangingTest.cancel()

      await #expect(throws: CancellationError.self) { try await hangingTest.value }
      #expect(try await waitUntilExited(processID: script))
      #expect(!tool.hasWaitingScript)
    }
  }
}

extension Sandbox {
  /// Writes the configuration the app writes, with a trampoline in place of the command, into the
  /// global configuration of the sandbox.
  func configureTool() throws -> ToolTrampoline {
    let tool = try ToolTrampoline(in: directory.appending(path: "tool"))
    try GitConfiguration(helper: tool.executable).write(using: git)
    return tool
  }
}
