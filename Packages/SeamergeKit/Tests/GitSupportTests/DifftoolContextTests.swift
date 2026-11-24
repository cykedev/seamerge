import Foundation
import GitSupport
import Testing

struct DifftoolContextTests {
  @Test func comparisonWithTheWorkingTreeHasAWorkingCopy() throws {
    try withSandbox { sandbox in
      let calls = try runDifftool(in: try sandbox.makeRepository("diff"), sandbox: sandbox)

      let contexts = calls.map(\.context)
      #expect(contexts.map(\.path) == ["one.txt", "three.txt", "two.txt"])
      #expect(contexts.allSatisfy { $0.leftRole == .before && $0.rightRole == .workingCopy })
      #expect(contexts.map(\.filePosition?.number) == [1, 2, 3])
      #expect(contexts.allSatisfy { $0.filePosition?.count == 3 })
    }
  }

  @Test(arguments: [
    ("diff-commits", ["notes.txt", "story.txt"]), ("diff-move", ["shapes.swift"]),
  ])
  func comparisonOfTwoCommitsHasNoWorkingCopy(scenario: String, paths: [String]) throws {
    try withSandbox { sandbox in
      let calls = try runDifftool(
        in: try sandbox.makeRepository(scenario), sandbox: sandbox,
        arguments: ["HEAD~1", "HEAD"])

      let contexts = calls.map(\.context)
      #expect(contexts.map(\.path) == paths)
      #expect(contexts.allSatisfy { $0.leftRole == .before && $0.rightRole == .after })
    }
  }

  @Test func addedAndDeletedFilesKeepTheirRoles() throws {
    try withSandbox { sandbox in
      let calls = try runDifftool(in: try sandbox.makeRepository("diff-new"), sandbox: sandbox)

      let added = try #require(calls.first { $0.context.path == "added.txt" })
      #expect(added.left == "/dev/null")
      #expect(added.context.leftRole == .before)
      #expect(added.context.rightRole == .workingCopy)
      let removed = try #require(calls.first { $0.context.path == "removed.txt" })
      #expect(removed.right == "/dev/null")
      #expect(removed.context.leftRole == .before)
      #expect(removed.context.rightRole == .after)
    }
  }

  @Test func workingCopyIsRecognizedThroughASymbolicLink() throws {
    try withSandbox { sandbox in
      let top = sandbox.directory.appending(path: "top", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
      try Data("text\n".utf8).write(to: top.appending(path: "file.txt"))
      let link = sandbox.directory.appending(path: "link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: top)

      let context = DifftoolContext.detect(
        path: "file.txt",
        leftFile: link.appending(path: "file.txt"),
        rightFile: URL(filePath: "/dev/null"),
        workingDirectory: top,
        environment: [:])

      #expect(context.leftRole == .workingCopy)
      #expect(context.rightRole == .after)
    }
  }

  @Test(arguments: [
    ["GIT_DIFF_PATH_COUNTER": "3"],
    ["GIT_DIFF_PATH_COUNTER": "0", "GIT_DIFF_PATH_TOTAL": "2"],
    ["GIT_DIFF_PATH_COUNTER": "3", "GIT_DIFF_PATH_TOTAL": "2"],
    ["GIT_DIFF_PATH_COUNTER": "one", "GIT_DIFF_PATH_TOTAL": "2"],
  ])
  func counterThatIsMissingOrDoesNotFitIsNoPosition(environment: [String: String]) {
    let context = DifftoolContext.detect(
      path: "file.txt",
      leftFile: URL(filePath: "/dev/null"),
      rightFile: URL(filePath: "/dev/null"),
      workingDirectory: URL(filePath: "/"),
      environment: environment)

    #expect(context.filePosition == nil)
  }

  @Test func contextMadeFromWhatTheToolHandedOverEqualsTheDetectedOne() {
    let detected = DifftoolContext.detect(
      path: "file.txt",
      leftFile: URL(filePath: "/dev/null"),
      rightFile: URL(filePath: "/dev/null"),
      workingDirectory: URL(filePath: "/"),
      environment: [:])

    #expect(DifftoolContext(path: "file.txt") == detected)
  }

  @Test func positionMadeFromItsNumbersEqualsTheOneGitPasses() {
    let context = DifftoolContext.detect(
      path: "file.txt",
      leftFile: URL(filePath: "/dev/null"),
      rightFile: URL(filePath: "/dev/null"),
      workingDirectory: URL(filePath: "/"),
      environment: ["GIT_DIFF_PATH_COUNTER": "2", "GIT_DIFF_PATH_TOTAL": "5"])

    #expect(context.filePosition == FilePosition(number: 2, count: 5))
  }

  /// One call of the tool by `git difftool`: what Git passed, and what was detected from it.
  private struct Call {
    var left: String
    var right: String
    var context: DifftoolContext
  }

  /// Runs `git difftool` with a tool that records each call, then detects the context of each.
  private func runDifftool(
    in repository: URL, sandbox: Sandbox, arguments: [String] = []
  ) throws -> [Call] {
    let log = sandbox.directory.appending(path: "calls.log")
    let tool = try sandbox.makeExecutable(
      "record",
      script: #"printf '%s\n' "$(pwd)" "$1" "$2" "$3" "$GIT_DIFF_PATH_COUNTER" "#
        + #""$GIT_DIFF_PATH_TOTAL" >> "$CALLS""#)
    let git = sandbox.git(adding: ["CALLS": log.path])
    let command = #"'\#(tool.path)' "$MERGED" "$LOCAL" "$REMOTE""#
    _ = try git.run(
      ["-c", "difftool.record.cmd=\(command)", "difftool", "--no-prompt", "--tool=record"]
        + arguments,
      in: repository)

    let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(
      String.init)
    return stride(from: 0, to: lines.count, by: 6).map { start in
      let call = Array(lines[start..<start + 6])
      let directory = URL(filePath: call[0], directoryHint: .isDirectory)
      let environment = ["GIT_DIFF_PATH_COUNTER": call[4], "GIT_DIFF_PATH_TOTAL": call[5]]
      return Call(
        left: call[2],
        right: call[3],
        context: DifftoolContext.detect(
          path: call[1],
          leftFile: URL(filePath: call[2], relativeTo: directory),
          rightFile: URL(filePath: call[3], relativeTo: directory),
          workingDirectory: directory,
          environment: environment))
    }
  }

  @Test func sideInTheWorkingTreeGivesThePathWhenTheOtherIsACopyOrMissing() throws {
    try withSandbox { sandbox in
      let temporary = sandbox.directory.appending(path: "T", directoryHint: .isDirectory)
      try Self.makeWorkingTree("repo", in: sandbox)
      let copy = try Self.makeFile("T/git-blob-taXZ1B/Greeting.swift", in: sandbox)
      let file = try Self.makeFile("repo/Sources/Greeting.swift", in: sandbox)
      let elsewhere = try Self.makeFile("elsewhere.swift", in: sandbox)
      func context(_ left: URL, _ right: URL) -> DifftoolContext? {
        DifftoolContext.inferred(
          leftFile: left, rightFile: right, git: sandbox.git(), temporaryDirectory: temporary,
          environment: [:])
      }

      #expect(
        context(copy, file)
          == DifftoolContext(
            path: "Sources/Greeting.swift", leftRole: .before, rightRole: .workingCopy))
      #expect(
        context(URL(filePath: "/dev/null"), file)
          == DifftoolContext(
            path: "Sources/Greeting.swift", leftRole: .before, rightRole: .workingCopy))
      #expect(
        context(file, URL(filePath: "/dev/null"))
          == DifftoolContext(
            path: "Sources/Greeting.swift", leftRole: .workingCopy, rightRole: .after))
      #expect(context(copy, copy) == nil)
      #expect(context(file, file) == nil)
      #expect(context(copy, elsewhere) == nil)
    }
  }

  /// Fork starts the tool in `/` and passes the copy of the index in its temporary folder, below
  /// the link `/var`, and the file in the working tree by its whole path.
  @Test func fileInAWorkingTreeElsewhereGivesItsPathInThatTree() throws {
    try withSandbox { sandbox in
      let temporary = sandbox.directory.appending(path: "T", directoryHint: .isDirectory)
      try #require(
        temporary.path.hasPrefix("/var/"), "The temporary folder lies below the link /var")
      try Self.makeWorkingTree("git tests/diff", in: sandbox)
      let copy = try Self.makeFile("T/fork/staged/sub dir/changed file.txt", in: sandbox)
      let file = try Self.makeFile("git tests/diff/sub dir/changed file.txt", in: sandbox)

      let context = DifftoolContext.inferred(
        leftFile: copy, rightFile: file, git: sandbox.git(), temporaryDirectory: temporary,
        environment: [:])

      #expect(
        context
          == DifftoolContext(
            path: "sub dir/changed file.txt", leftRole: .before, rightRole: .workingCopy))
    }
  }

  @Test func fileReachedThroughALinkGivesItsPathInTheWorkingTree() throws {
    try withSandbox { sandbox in
      let temporary = sandbox.directory.appending(path: "T", directoryHint: .isDirectory)
      let tree = try Self.makeWorkingTree("repo", in: sandbox)
      let copy = try Self.makeFile("T/git-blob-taXZ1B/Greeting.swift", in: sandbox)
      try Self.makeFile("repo/Sources/Greeting.swift", in: sandbox)
      let link = sandbox.directory.appending(path: "link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tree)

      let context = DifftoolContext.inferred(
        leftFile: copy, rightFile: link.appending(path: "Sources/Greeting.swift"),
        git: sandbox.git(), temporaryDirectory: temporary, environment: [:])

      #expect(
        context
          == DifftoolContext(
            path: "Sources/Greeting.swift", leftRole: .before, rightRole: .workingCopy))
    }
  }

  /// A file outside every working tree has no path of Git, wherever the tool runs; its name
  /// stays the name of the file.
  @Test func fileOutsideAWorkingTreeGivesNoPath() throws {
    try withSandbox { sandbox in
      let temporary = sandbox.directory.appending(path: "T", directoryHint: .isDirectory)
      let copy = try Self.makeFile("T/fork/staged/sub dir/changed file.txt", in: sandbox)
      let file = try Self.makeFile("notes/sub dir/changed file.txt", in: sandbox)

      let context = DifftoolContext.inferred(
        leftFile: copy, rightFile: file, git: sandbox.git(), temporaryDirectory: temporary,
        environment: [:])

      #expect(context == nil)
    }
  }

  @Test func inferredContextTakesThePositionFromTheEnvironment() throws {
    try withSandbox { sandbox in
      let temporary = sandbox.directory.appending(path: "T", directoryHint: .isDirectory)
      try Self.makeWorkingTree("repo", in: sandbox)
      let copy = try Self.makeFile("T/git-blob-taXZ1B/Greeting.swift", in: sandbox)
      let file = try Self.makeFile("repo/Greeting.swift", in: sandbox)

      let context = DifftoolContext.inferred(
        leftFile: copy, rightFile: file, git: sandbox.git(), temporaryDirectory: temporary,
        environment: ["GIT_DIFF_PATH_COUNTER": "2", "GIT_DIFF_PATH_TOTAL": "5"])

      #expect(context?.filePosition == FilePosition(number: 2, count: 5))
    }
  }

  /// Makes an empty repository at `path` in `sandbox` and returns the top of its working tree.
  @discardableResult
  private static func makeWorkingTree(_ path: String, in sandbox: Sandbox) throws -> URL {
    let tree = sandbox.directory.appending(path: path, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    _ = try sandbox.git().run(["init", "--quiet"], in: tree)
    return tree
  }

  /// Writes a line into a new file at `path` in `sandbox` and returns its location.
  @discardableResult
  private static func makeFile(_ path: String, in sandbox: Sandbox) throws -> URL {
    let url = sandbox.directory.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("line\n".utf8).write(to: url)
    return url
  }

  @Test func originTellsMissingSidesAndCopiesFromOtherFiles() {
    let temporary = URL(filePath: "/private/var/folders/xy/T/", directoryHint: .isDirectory)
    func origin(_ path: String) -> FileOrigin {
      FileOrigin(url: URL(filePath: path), temporaryDirectory: temporary)
    }

    #expect(origin("/dev/null") == .missing)
    #expect(origin("/private/var/folders/xy/T/git-blob-QQ1247/notes.txt") == .temporaryCopy)
    #expect(origin("/tmp/notes.txt") == .temporaryCopy)
    #expect(origin("/Users/ada/Projects/app/notes.txt") == .ordinary)
  }
}
