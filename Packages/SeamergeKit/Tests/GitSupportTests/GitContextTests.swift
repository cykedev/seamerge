import Foundation
import GitSupport
import Testing

struct GitContextTests {
  @Test func mergeNamesTheIncomingBranchAndTheCurrentBranch() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let git = sandbox.git()

      let context = detect(in: repository, file: "story.txt", git: git)

      #expect(context.operation == .merge)
      #expect(context.remote.name == .reference("feature"))
      #expect(context.remote.role == .incoming)
      #expect(context.remote.commit?.subject == "Change line 5 on feature")
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == .yours)
      #expect(context.local.commit?.subject == "Change line 5 on main")
      let base = try git.output(["log", "-1", "--format=%h", "main~1"], in: repository)
      #expect(context.base.name == .commit(abbreviatedHash: base, subject: nil, branch: nil))
      #expect(context.base.role == nil)
      #expect(context.base.commit?.subject == "Add story.txt")
      #expect(context.rebaseProgress == nil)
      #expect(context.remainingConflictedFileCount == 0)
      #expect(context.hasCommonAncestor)
    }
  }

  @Test func fileBothSidesAddedHasNoCommonAncestor() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("add-add")

      let context = detect(in: repository, file: "added.txt", git: sandbox.git())

      #expect(!context.hasCommonAncestor)
      #expect(context.base == MergeSide())
      #expect(context.remote.name == .reference("feature"))
      #expect(context.local.name == .reference("main"))
    }
  }

  @Test func emptyCommonAncestorIsStillACommonAncestor() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let git = sandbox.git()
      let file = repository.appending(path: "empty.txt")
      func commit(_ text: String, _ message: String) throws {
        try Data(text.utf8).write(to: file)
        _ = try git.run(["add", "empty.txt"], in: repository)
        _ = try git.run(["commit", "--quiet", "--message", message], in: repository)
      }
      _ = try git.run(["stash", "--quiet"], in: repository)
      try commit("", "Add an empty file")
      _ = try git.run(["switch", "--quiet", "--create", "feature"], in: repository)
      try commit("from feature\n", "Fill the file on feature")
      _ = try git.run(["switch", "--quiet", "main"], in: repository)
      try commit("from main\n", "Fill the file on main")
      #expect(throws: GitError.self) { try git.run(["merge", "feature"], in: repository) }

      let context = detect(in: repository, file: "empty.txt", git: git)

      #expect(context.hasCommonAncestor)
      #expect(context.base.commit != nil)
    }
  }

  @Test func rebaseSwapsTheSidesAndCountsTheCommits() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let git = sandbox.git()

      let context = detect(in: repository, file: "notes.txt", git: git)

      let stopped = try git.output(["log", "-1", "--format=%h", "feature~1"], in: repository)
      #expect(context.operation == .rebase)
      #expect(
        context.remote.name
          == .commit(abbreviatedHash: stopped, subject: "Change line 5", branch: "feature"))
      #expect(context.remote.role == .yourCommit)
      #expect(context.remote.commit?.abbreviatedHash == stopped)
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == .rebaseTarget)
      #expect(context.local.commit?.subject == "Change line 2")
      let progress = try #require(context.rebaseProgress)
      #expect(progress.targetName == .reference("main"))
      #expect(progress.commitNumber == 2)
      #expect(progress.commitCount == 3)
    }
  }

  @Test func cherryPickNamesThePickedCommit() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("cherry-pick")
      let git = sandbox.git()

      let context = detect(in: repository, file: "story.txt", git: git)

      let picked = try git.output(["log", "-1", "--format=%h", "feature"], in: repository)
      #expect(context.operation == .cherryPick)
      #expect(
        context.remote.name
          == .commit(abbreviatedHash: picked, subject: "Change line 5 on feature", branch: nil))
      #expect(context.remote.role == .cherryPickedCommit)
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == .yours)
      #expect(context.rebaseProgress == nil)
    }
  }

  @Test func revertNamesTheRevertedCommit() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("revert")
      let git = sandbox.git()

      let context = detect(in: repository, file: "story.txt", git: git)

      let reverted = try git.output(["log", "-1", "--format=%h", "HEAD~1"], in: repository)
      #expect(context.operation == .revert)
      #expect(
        context.remote.name
          == .commit(abbreviatedHash: reverted, subject: "Change line 5", branch: nil))
      #expect(context.remote.role == .revertedCommit)
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == nil)
    }
  }

  @Test func stashReplacesTheLabelsGitMakesUp() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("stash")

      let context = detect(in: repository, file: "story.txt", git: sandbox.git())

      #expect(context.operation == .stash)
      #expect(context.remote == MergeSide(name: .stash))
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == nil)
      #expect(context.local.commit?.subject == "Change line 5 on main")
    }
  }

  @Test(arguments: [
    ("add-add", "added.txt"), ("whitespace", "code.txt"), ("crlf", "story.txt"),
    ("utf16", "greeting.txt"), ("big", "big.txt"),
  ])
  func everyMergeScenarioNamesBothBranches(scenario: String, file: String) throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository(scenario)

      let context = detect(in: repository, file: file, git: sandbox.git())

      #expect(context.operation == .merge)
      #expect(context.remote.name == .reference("feature"))
      #expect(context.remote.role == .incoming)
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == .yours)
      #expect(context.remainingConflictedFileCount == 0)
    }
  }

  @Test func otherConflictedFilesAreCountedWithoutTheMergedOne() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("many")

      let context = detect(in: repository, file: "file-07.txt", git: sandbox.git())

      #expect(context.remainingConflictedFileCount == 11)
    }
  }

  @Test func resolvedFilesAreNotCounted() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("many")
      let git = sandbox.git()
      _ = try git.run(["checkout", "--theirs", "--", "file-01.txt", "file-02.txt"], in: repository)
      _ = try git.run(["add", "--", "file-01.txt", "file-02.txt"], in: repository)

      let context = detect(in: repository, file: "file-07.txt", git: git)

      #expect(context.remainingConflictedFileCount == 9)
    }
  }

  @Test func mergedFileWithADecomposedNameIsStillRecognized() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("many")
      // Git lists the name precomposed; the file system keeps the form a file was created with.
      // Swift compares and hashes both forms as equal.
      let precomposed = repository.appending(path: "Grüße.txt")
      let decomposed = repository.appending(path: "Gru\u{0308}ße.txt")
      let content = try Data(contentsOf: precomposed)
      try FileManager.default.removeItem(at: precomposed)
      try content.write(to: decomposed)
      let names = try FileManager.default.contentsOfDirectory(atPath: repository.path)
      #expect(names.map { Array($0.utf8) }.contains(Array("Gru\u{0308}ße.txt".utf8)))

      let context = detect(in: repository, file: "Gru\u{0308}ße.txt", git: sandbox.git())

      #expect(context.remainingConflictedFileCount == 11)
    }
  }

  @Test func mergedFileGivenFromASubdirectoryIsStillRecognized() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("many")
      let subdirectory = repository.appending(path: "sub", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)

      let context = GitContext.detect(
        workingDirectory: subdirectory,
        mergedFile: subdirectory.appending(path: "../file-03.txt"),
        git: sandbox.git())

      #expect(context.remainingConflictedFileCount == 11)
    }
  }

  @Test func markerLabelOtherThanHeadNamesTheSide() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let file = repository.appending(path: "story.txt")
      try Data("<<<<<<< mine\na\n=======\nb\n>>>>>>> topic/v2\n".utf8).write(to: file)

      let context = detect(in: repository, file: "story.txt", git: sandbox.git())

      #expect(context.remote.name == .reference("topic/v2"))
      #expect(context.remote.role == .incoming)
      #expect(context.local.name == .reference("mine"))
    }
  }

  @Test func withoutMarkersTheRepositoryNamesTheSides() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      try Data("resolved\n".utf8).write(to: repository.appending(path: "story.txt"))

      let context = detect(in: repository, file: "story.txt", git: sandbox.git())

      #expect(context.remote.name == .reference("feature"))
      #expect(context.local.name == .reference("main"))
    }
  }

  @Test func missingMergedFileLeavesTheRepositoryAsSource() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("cherry-pick")

      let context = detect(in: repository, file: "does-not-exist.txt", git: sandbox.git())

      #expect(context.operation == .cherryPick)
      #expect(context.remote.role == .cherryPickedCommit)
      #expect(context.local.name == .reference("main"))
      #expect(context.remainingConflictedFileCount == 1)
    }
  }

  @Test func outsideARepositoryOnlyTheMarkerLabelsRemain() throws {
    try withSandbox { sandbox in
      let file = sandbox.directory.appending(path: "merged.txt")
      let text = "<<<<<<< HEAD\na\n||||||| base\nc\n=======\nb\n>>>>>>> 1a2b3c4 (Fix it)\n"
      try Data(text.utf8).write(to: file)

      let context = GitContext.detect(
        workingDirectory: sandbox.directory, mergedFile: file, git: sandbox.git())

      #expect(context.operation == nil)
      #expect(context.local == MergeSide(name: .reference("HEAD")))
      #expect(
        context.remote
          == MergeSide(name: .commit(abbreviatedHash: "1a2b3c4", subject: "Fix it", branch: nil)))
      #expect(context.base == MergeSide(name: .reference("base")))
      #expect(context.rebaseProgress == nil)
      #expect(context.remainingConflictedFileCount == nil)
    }
  }

  @Test func mergedFileOutsideTheRepositoryOfTheWorkingDirectoryLeavesItOut() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let elsewhere = sandbox.directory.appending(path: "elsewhere", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
      let file = elsewhere.appending(path: "story.txt")
      try Data("<<<<<<< HEAD\na\n=======\nb\n>>>>>>> other\n".utf8).write(to: file)

      let context = GitContext.detect(
        workingDirectory: repository, mergedFile: file, git: sandbox.git())

      #expect(context.operation == nil)
      #expect(context.local == MergeSide(name: .reference("HEAD")))
      #expect(context.remote == MergeSide(name: .reference("other")))
      #expect(context.remainingConflictedFileCount == nil)
    }
  }

  @Test func mergedFileReachedThroughASymbolicLinkStillBelongsToTheRepository() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let link = sandbox.directory.appending(path: "link", directoryHint: .isDirectory)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repository)

      let context = GitContext.detect(
        workingDirectory: repository, mergedFile: link.appending(path: "story.txt"),
        git: sandbox.git())

      #expect(context.operation == .merge)
      #expect(context.local.name == .reference("main"))
    }
  }

  @Test func outsideARepositoryStashMarkersStillNameTheStash() throws {
    try withSandbox { sandbox in
      let file = sandbox.directory.appending(path: "merged.txt")
      let text = "<<<<<<< Updated upstream\na\n=======\nb\n>>>>>>> Stashed changes\n"
      try Data(text.utf8).write(to: file)

      let context = GitContext.detect(
        workingDirectory: sandbox.directory, mergedFile: file, git: sandbox.git())

      #expect(context.operation == .stash)
      #expect(context.remote == MergeSide(name: .stash))
      #expect(context.local == MergeSide())
    }
  }

  @Test func withoutAnySourceNoSideHasAName() throws {
    try withSandbox { sandbox in
      let file = sandbox.directory.appending(path: "merged.txt")
      try Data("no conflict here\n".utf8).write(to: file)

      let context = GitContext.detect(
        workingDirectory: sandbox.directory, mergedFile: file, git: sandbox.git())

      #expect(context.operation == nil)
      #expect(context.remote == MergeSide())
      #expect(context.local == MergeSide())
      #expect(context.base == MergeSide())
    }
  }

  @Test func damagedMergeHeadLeavesOutOnlyWhatDependsOnIt() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      try Data("--output=/tmp/x\n".utf8).write(to: repository.appending(path: ".git/MERGE_HEAD"))

      let context = detect(in: repository, file: "story.txt", git: sandbox.git())

      #expect(context.operation == .merge)
      #expect(context.remote == MergeSide(name: .reference("feature"), role: .incoming))
      #expect(context.local.name == .reference("main"))
      #expect(context.base == MergeSide())
      #expect(context.remainingConflictedFileCount == 0)
    }
  }

  @Test func damagedRebaseCountersLeaveOutOnlyTheProgress() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let state = repository.appending(path: ".git/rebase-merge")
      try Data("two\n".utf8).write(to: state.appending(path: "msgnum"))

      let context = detect(in: repository, file: "notes.txt", git: sandbox.git())

      #expect(context.operation == .rebase)
      #expect(context.rebaseProgress == nil)
      #expect(context.remote.role == .yourCommit)
      #expect(context.local.name == .reference("main"))
    }
  }

  @Test func rebaseCountersBeyondTheEndAreIgnored() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let state = repository.appending(path: ".git/rebase-merge")
      try Data("4\n".utf8).write(to: state.appending(path: "msgnum"))

      let context = detect(in: repository, file: "notes.txt", git: sandbox.git())

      #expect(context.rebaseProgress == nil)
    }
  }

  @Test func olderRebaseBackendSwapsTheSidesAndCountsTheCommits() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let git = sandbox.git()
      _ = try git.run(["rebase", "--abort"], in: repository)
      #expect(throws: GitError.self) { try git.run(["rebase", "--apply", "main"], in: repository) }

      let context = detect(in: repository, file: "notes.txt", git: git)

      let stopped = try git.output(["log", "-1", "--format=%h", "feature~1"], in: repository)
      #expect(context.operation == .rebase)
      #expect(
        context.remote.name
          == .commit(abbreviatedHash: stopped, subject: "Change line 5", branch: "feature"))
      #expect(context.remote.role == .yourCommit)
      #expect(context.local.name == .reference("main"))
      #expect(context.local.role == .rebaseTarget)
      let progress = try #require(context.rebaseProgress)
      #expect(progress.targetName == .reference("main"))
      #expect(progress.commitNumber == 2)
      #expect(progress.commitCount == 3)
    }
  }

  @Test func headLabelWithoutARecognizedOperationNamesTheCurrentBranch() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("cherry-pick")
      let git = sandbox.git()
      _ = try git.run(["cherry-pick", "--abort"], in: repository)
      let patch = sandbox.directory.appending(path: "change.patch")
      try git.run(["format-patch", "-1", "--stdout", "feature"], in: repository).write(to: patch)
      #expect(throws: GitError.self) { try git.run(["am", "-3", patch.path], in: repository) }

      let context = detect(in: repository, file: "story.txt", git: git)

      #expect(context.operation == nil)
      #expect(context.local == MergeSide(name: .reference("main")))
      #expect(context.remote == MergeSide(name: .reference("Change line 5 on feature")))
    }
  }

  @Test func applyingMailboxIsNoRebase() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let state = repository.appending(path: ".git/rebase-apply", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
      try Data().write(to: state.appending(path: "applying"))

      let context = detect(in: repository, file: "one.txt", git: sandbox.git())

      #expect(context.operation == nil)
    }
  }

  @Test func gitThatFailsLeavesTheMarkerLabels() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let bin = try sandbox.makeExecutable("git", script: "exit 1").deletingLastPathComponent()
      let git = Git(environment: sandbox.environment.merging(["PATH": bin.path]) { $1 })

      let context = detect(in: repository, file: "story.txt", git: git)

      #expect(context.operation == nil)
      #expect(context.remote == MergeSide(name: .reference("feature")))
      #expect(context.local == MergeSide(name: .reference("HEAD")))
    }
  }

  @Test func gitThatHangsIsStoppedAndLeavesTheMarkerLabels() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      let bin = try sandbox.makeExecutable("git", script: "exec /bin/sleep 30")
        .deletingLastPathComponent()
      let environment = sandbox.environment.merging(["PATH": bin.path]) { $1 }
      let git = Git(environment: environment, timeout: .milliseconds(200))
      let start = ContinuousClock.now

      let context = detect(in: repository, file: "story.txt", git: git)

      #expect(ContinuousClock.now - start < .seconds(5))
      #expect(context.remote == MergeSide(name: .reference("feature")))
    }
  }

  private func detect(in repository: URL, file: String, git: Git) -> GitContext {
    GitContext.detect(
      workingDirectory: repository, mergedFile: repository.appending(path: file), git: git)
  }
}
