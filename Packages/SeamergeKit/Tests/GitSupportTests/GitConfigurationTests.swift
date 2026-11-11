import Foundation
import GitSupport
import Testing

struct GitConfigurationTests {
  @Test func commandsForTheAppInApplicationsNeedNoQuotesAroundThePath() {
    let helper = URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge")

    let commands = GitConfiguration(helper: helper).commands

    let path = helper.path
    #expect(
      commands == [
        "git config --global merge.tool seamerge",
        #"git config --global mergetool.seamerge.cmd '\#(path) merge --base "$BASE" "#
          + #"--local "$LOCAL" --remote "$REMOTE" --output "$MERGED"'"#,
        "git config --global mergetool.seamerge.trustExitCode true",
        "git config --global mergetool.prompt false",
        "git config --global mergetool.keepBackup false",
        "git config --global diff.tool seamerge",
        #"git config --global difftool.seamerge.cmd '\#(path) diff --path "$MERGED" "#
          + #"-- "$LOCAL" "$REMOTE"'"#,
        "git config --global difftool.prompt false",
        "git config --global difftool.trustExitCode true",
      ])
  }

  @Test func commandsRunInAShellWriteTheEntries() throws {
    try withSandbox { sandbox in
      let helper = URL(filePath: #"/Users/ada/It's "my" $HOME/Seamerge.app/seamerge"#)
      let configuration = GitConfiguration(helper: helper)

      for command in configuration.commands {
        let result = try runProcess(
          URL(filePath: "/bin/sh"), arguments: ["-c", command], environment: sandbox.environment)
        try #require(result.status == 0, "\(command): \(result.output)")
      }

      let git = sandbox.git()
      for entry in configuration.entries {
        #expect(
          try git.output(["config", "--global", "--get", entry.key], in: sandbox.directory)
            == entry.value)
      }
    }
  }

  @Test func replacementsNameOnlyTheValuesThatWouldChange() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration(
        """
        [merge]
        \ttool = Kaleidoscope
        [diff]
        \ttool = Kaleidoscope
        [mergetool]
        \tprompt = false
        [mergetool "Kaleidoscope"]
        \tcmd = ksdiff --merge
        """, in: sandbox)
      let configuration = GitConfiguration(helper: URL(filePath: "/Applications/Seamerge.app"))
      let git = sandbox.git()

      let replacements = try configuration.replacements(using: git)

      #expect(replacements.map(\.key) == ["merge.tool", "diff.tool"])
      #expect(replacements.map(\.currentValue) == ["Kaleidoscope", "Kaleidoscope"])
      #expect(replacements.map(\.newValue) == ["seamerge", "seamerge"])
    }
  }

  @Test func writingKeepsTheEntriesOfOtherTools() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration(
        "[merge]\n\ttool = Kaleidoscope\n[mergetool \"Kaleidoscope\"]\n\tcmd = ksdiff --merge\n",
        in: sandbox)
      let configuration = GitConfiguration(helper: URL(filePath: "/Applications/Seamerge.app"))
      let git = sandbox.git()

      try configuration.write(using: git)

      #expect(try configuration.replacements(using: git).isEmpty)
      let other = try git.output(
        ["config", "--global", "--get", "mergetool.Kaleidoscope.cmd"], in: sandbox.directory)
      #expect(other == "ksdiff --merge")
    }
  }

  @Test func writingLeavesOneValueForAKeyWithSeveral() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration(
        "[mergetool]\n\tprompt = true\n\tprompt = true\n", in: sandbox)
      let git = sandbox.git()

      try GitConfiguration(helper: URL(filePath: "/Applications/Seamerge.app")).write(using: git)

      let values = try git.output(
        ["config", "--global", "--get-all", "mergetool.prompt"], in: sandbox.directory)
      #expect(values == "false")
    }
  }

  @Test func unreadableConfigurationIsAnError() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration("[merge\n", in: sandbox)
      let configuration = GitConfiguration(helper: URL(filePath: "/Applications/Seamerge.app"))

      #expect(throws: GitError.self) { try configuration.replacements(using: sandbox.git()) }
    }
  }

  @Test func writtenConfigurationMakesTheHelperTheMergetool() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("rebase")
      let helper = try makeRecordingHelper(in: sandbox)
      let git = sandbox.git()
      try GitConfiguration(helper: helper).write(using: git)

      _ = try git.run(["mergetool"], in: repository)

      let arguments = try recordedArguments(of: helper)
      #expect(arguments.count == 9)
      #expect(arguments.first == "merge")
      #expect(arguments.last == "notes.txt")
      // In a rebase, REMOTE is the user's own commit.
      let remote = try String(contentsOf: helper.appendingPathExtension("remote"), encoding: .utf8)
      #expect(remote.contains("line 5 from feature"))
      #expect(try git.output(["diff", "--name-only", "--diff-filter=U"], in: repository).isEmpty)
      #expect(
        !FileManager.default.fileExists(atPath: repository.appending(path: "notes.txt.orig").path))
    }
  }

  @Test func writtenConfigurationMakesTheHelperTheDifftool() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let helper = try makeRecordingHelper(in: sandbox)
      let git = sandbox.git()
      try GitConfiguration(helper: helper).write(using: git)

      _ = try git.run(["difftool"], in: repository)

      let arguments = try recordedArguments(of: helper)
      #expect(arguments.count == 6)
      #expect(Array(arguments.prefix(3)) == ["diff", "--path", "two.txt"])
      #expect(arguments[3] == "--")
      #expect(arguments.last == "two.txt")
    }
  }

  @Test func fileWhoseNameStartsWithADashFollowsTheEndOfTheOptions() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let file = repository.appending(path: "-x.txt")
      try Data("first\n".utf8).write(to: file)
      let git = sandbox.git()
      _ = try git.run(["add", "--", "-x.txt"], in: repository)
      _ = try git.run(["commit", "--quiet", "--message", "Add -x.txt"], in: repository)
      try Data("second\n".utf8).write(to: file)
      let helper = try makeRecordingHelper(in: sandbox)
      try GitConfiguration(helper: helper).write(using: git)

      _ = try git.run(["difftool", "--", "-x.txt"], in: repository)

      let arguments = try recordedArguments(of: helper)
      #expect(arguments.count == 6)
      #expect(Array(arguments.prefix(4)) == ["diff", "--path", "-x.txt", "--"])
      #expect(arguments[4].hasSuffix("x.txt"))
      #expect(arguments[5] == "-x.txt")
    }
  }

  @Test func failingComparisonEndsTheDifftoolRun() throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("diff")
      let helper = try makeRecordingHelper(in: sandbox, exitStatus: 1)
      let git = sandbox.git()
      try GitConfiguration(helper: helper).write(using: git)

      #expect(throws: GitError.self) { try git.run(["difftool"], in: repository) }

      let calls = try String(contentsOf: helper.appendingPathExtension("calls"), encoding: .utf8)
      #expect(calls == "diff\n")
    }
  }

  /// A helper that records its calls in files next to it.
  ///
  /// It records its arguments and, for a merge, the content of `REMOTE`. Its folder has
  /// characters a shell treats specially.
  private func makeRecordingHelper(in sandbox: Sandbox, exitStatus: Int = 0) throws -> URL {
    try sandbox.makeExecutable(
      "seamerge", in: #"It's "my" $HOME"#,
      script: """
        printf '%s\\n' "$@" > "$0.arguments"
        printf '%s\\n' "$1" >> "$0.calls"
        if [ "$1" = merge ]; then cp "$7" "$0.remote"; fi
        exit \(exitStatus)
        """)
  }

  private func recordedArguments(of helper: URL) throws -> [String] {
    let text = try String(contentsOf: helper.appendingPathExtension("arguments"), encoding: .utf8)
    return text.split(separator: "\n").map(String.init)
  }

  private func writeGlobalConfiguration(_ text: String, in sandbox: Sandbox) throws {
    try Data(text.utf8).write(to: sandbox.globalConfiguration)
  }
}
