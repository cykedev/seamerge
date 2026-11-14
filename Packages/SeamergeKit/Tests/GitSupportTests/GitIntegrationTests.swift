import Foundation
import GitSupport
import Testing

/// Setting up and removing the integration on a configuration of its own: what it reads, what it
/// remembers, and that removing leaves the configuration as it was.
struct GitIntegrationTests {
  private let helper = URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge")

  @Test func emptyConfigurationUsesNoToolAndHasEverySwitchOn() throws {
    try withSandbox { sandbox in
      let state = try GitIntegration(helper: helper, git: sandbox.git()).state()

      #expect(
        state
          == GitIntegrationState(
            merge: .none, diff: .none,
            changedSwitches: [
              .prompt, .keepBackup,
            ]))
    }
  }

  @Test func stateNamesTheOtherToolsAndWhatIsSetUp() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration(
        """
        [merge]
        \ttool = Kaleidoscope
        [diff]
        \ttool = FileMerge
        [mergetool]
        \tprompt = no
        \tkeepBackup = off
        [difftool]
        \tprompt = false
        """, in: sandbox)
      let integration = GitIntegration(helper: helper, git: sandbox.git())

      #expect(
        try integration.state()
          == GitIntegrationState(
            merge: .other("Kaleidoscope"), diff: .other("FileMerge"), changedSwitches: []))

      _ = try integration.setUp(keeping: nil)
      #expect(
        try integration.state()
          == GitIntegrationState(merge: .seamerge, diff: .seamerge, changedSwitches: []))
    }
  }

  @Test func onlyOneToolCanBeSetUp() throws {
    try withSandbox { sandbox in
      let integration = GitIntegration(helper: helper, git: sandbox.git())
      _ = try integration.setUp(keeping: nil)
      _ = try sandbox.git().run(["config", "--global", "diff.tool", "opendiff"])

      let state = try integration.state()

      #expect(state.merge == .seamerge)
      #expect(state.diff == .other("opendiff"))
    }
  }

  @Test func entriesOfAnotherCopyAreSeenAsMoved() throws {
    try withSandbox { sandbox in
      let oldHelper = URL(
        filePath: "/Users/ada/Downloads/It's Seamerge.app/Contents/Helpers/seamerge")
      _ = try GitIntegration(helper: oldHelper, git: sandbox.git()).setUp(keeping: nil)

      let state = try GitIntegration(helper: helper, git: sandbox.git()).state()

      #expect(state.merge == .movedSeamerge(helper: oldHelper.path))
      #expect(state.diff == .movedSeamerge(helper: oldHelper.path))
    }
  }

  @Test func commandOfAnEarlierVersionOfThisCopyIsSeenAsOutdated() throws {
    try withSandbox { sandbox in
      let git = sandbox.git()
      _ = try GitIntegration(helper: helper, git: git).setUp(keeping: nil)
      _ = try git.run([
        "config", "--global", "difftool.seamerge.cmd",
        #"\#(helper.path) diff --path "$MERGED" -- "$LOCAL" "$REMOTE""#,
      ])

      let state = try GitIntegration(helper: helper, git: git).state()

      #expect(state.merge == .seamerge)
      #expect(state.diff == .outdatedSeamerge)
    }
  }

  @Test func commandTheUserChangedIsNotTakenForAnEarlierVersion() throws {
    try withSandbox { sandbox in
      let git = sandbox.git()
      _ = try GitIntegration(helper: helper, git: git).setUp(keeping: nil)
      _ = try git.run([
        "config", "--global", "difftool.seamerge.cmd",
        #"\#(helper.path) diff --collect --label-left old --path "$MERGED" -- "$LOCAL" "$REMOTE""#,
      ])

      let state = try GitIntegration(helper: helper, git: git).state()

      #expect(state.diff == .changedSeamerge)
    }
  }

  @Test func systemConfigurationCountsLikeTheGlobalOne() throws {
    try withSandbox { sandbox in
      let system = sandbox.directory.appending(path: "gitconfig-system")
      try Data("[merge]\n\ttool = vimdiff\n".utf8).write(to: system)
      let git = sandbox.git(adding: ["GIT_CONFIG_NOSYSTEM": "0", "GIT_CONFIG_SYSTEM": system.path])

      #expect(try GitIntegration(helper: helper, git: git).state().merge == .other("vimdiff"))
    }
  }

  @Test func removingAfterSetUpLeavesTheConfigurationAsItWas() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration(
        """
        [user]
        \tname = Ada
        [merge]
        \ttool = Kaleidoscope
        [diff]
        \ttool = Kaleidoscope
        [mergetool "Kaleidoscope"]
        \tcmd = ksdiff --merge --output \\"$MERGED\\"
        \ttrustExitCode = true
        [mergetool]
        \tprompt = true
        """, in: sandbox)
      let git = sandbox.git()
      let before = try entries(of: git)
      let integration = GitIntegration(helper: helper, git: git)

      let backup = try integration.setUp(keeping: nil)
      #expect(try entries(of: git) != before)
      #expect(backup.restoredTools.merge == "Kaleidoscope")
      try integration.remove(restoring: backup)

      #expect(try entries(of: git) == before)
    }
  }

  @Test func removingFromAnEmptyConfigurationLeavesItEmpty() throws {
    try withSandbox { sandbox in
      let git = sandbox.git()
      let integration = GitIntegration(helper: helper, git: git)

      let backup = try integration.setUp(keeping: nil)
      try integration.remove(restoring: backup)

      #expect(try entries(of: git).isEmpty)
      #expect(backup.restoredTools == (nil, nil))
    }
  }

  @Test func keyTheUserChangedSinceStays() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration("[merge]\n\ttool = Kaleidoscope\n", in: sandbox)
      let git = sandbox.git()
      let integration = GitIntegration(helper: helper, git: git)
      let backup = try integration.setUp(keeping: nil)
      _ = try git.run(["config", "--global", "diff.tool", "opendiff"])
      _ = try git.run(["config", "--global", "mergetool.prompt", "true"])

      try integration.remove(restoring: backup)

      #expect(
        try entries(of: git)
          == ["diff.tool=opendiff", "merge.tool=Kaleidoscope", "mergetool.prompt=true"])
    }
  }

  @Test func settingUpAgainKeepsWhatTheFirstSetupRemembered() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration("[merge]\n\ttool = Kaleidoscope\n", in: sandbox)
      let git = sandbox.git()
      let before = try entries(of: git)
      let oldIntegration = GitIntegration(
        helper: URL(filePath: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
        git: git)
      let first = try oldIntegration.setUp(keeping: nil)
      let integration = GitIntegration(helper: helper, git: git)

      let second = try integration.setUp(keeping: first)
      try integration.remove(restoring: second)

      #expect(second == first)
      #expect(try entries(of: git) == before)
    }
  }

  @Test func earlierCopySetUpByHandIsNotRestored() throws {
    try withSandbox { sandbox in
      let git = sandbox.git()
      _ = try GitIntegration(
        helper: URL(filePath: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
        git: git
      ).setUp(keeping: nil)
      let integration = GitIntegration(helper: helper, git: git)

      let backup = try integration.setUp(keeping: nil)
      try integration.remove(restoring: backup)

      #expect(backup.restoredTools == (nil, nil))
      #expect(try entries(of: git).allSatisfy { !$0.contains("seamerge") })
    }
  }

  @Test func removingWithoutBackupTakesOnlyTheToolAndLeavesTheSwitches() throws {
    try withSandbox { sandbox in
      let git = sandbox.git()
      let integration = GitIntegration(helper: helper, git: git)
      for command in integration.configuration.commands {
        let result = try runProcess(
          URL(filePath: "/bin/sh"), arguments: ["-c", command], environment: sandbox.environment)
        try #require(result.status == 0, "\(command): \(result.output)")
      }

      try integration.remove(restoring: nil)

      #expect(
        try entries(of: git) == [
          "difftool.prompt=false", "difftool.trustexitcode=true", "mergetool.keepbackup=false",
          "mergetool.prompt=false",
        ])
    }
  }

  @Test func failedSetupRestoresWhatItHadWritten() throws {
    try withSandbox { sandbox in
      try writeGlobalConfiguration("[merge]\n\ttool = Kaleidoscope\n", in: sandbox)
      let git = sandbox.git()
      let before = try entries(of: git)
      // A `git` that refuses to write the name of the diff tool, after the merge entries.
      let failing = try sandbox.makeExecutable(
        "git",
        script: """
          case "$*" in *"--replace-all diff.tool "*) echo "error: cannot lock" >&2; exit 255;; esac
          exec '\(git.executableURL.path)' "$@"
          """)
      let path =
        failing.deletingLastPathComponent().path + ":" + (sandbox.environment["PATH"] ?? "")
      let integration = GitIntegration(helper: helper, git: sandbox.git(adding: ["PATH": path]))

      #expect(throws: GitError.self) { try integration.setUp(keeping: nil) }

      #expect(try entries(of: git) == before)
    }
  }

  /// The entries of the global configuration, as `key=value` lines in their order of keys.
  private func entries(of git: Git) throws -> [String] {
    let list: String
    do {
      list = String(decoding: try git.run(["config", "--global", "--list"]), as: UTF8.self)
    } catch .failed(_, status: 1, _) {
      return []
    }
    return list.split(separator: "\n").map(String.init).sorted()
  }
}
