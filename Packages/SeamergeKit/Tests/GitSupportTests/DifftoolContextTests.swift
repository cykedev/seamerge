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

  @Test func comparisonOfTwoCommitsHasNoWorkingCopy() throws {
    try withSandbox { sandbox in
      let calls = try runDifftool(
        in: try sandbox.makeRepository("diff-commits"), sandbox: sandbox,
        arguments: ["HEAD~1", "HEAD"])

      let contexts = calls.map(\.context)
      #expect(contexts.map(\.path) == ["notes.txt", "story.txt"])
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
}
