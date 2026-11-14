import Foundation
import GitSupport
import Testing

/// Tower's list of tools in a folder of its own: what adding says beforehand, that other tools
/// stay, and that the script hands the files to the helper.
struct TowerConfigurationTests {
  @Test func addingCreatesTheListAndAnExecutableScript() throws {
    try withSandbox { sandbox in
      let tower = configuration(in: sandbox)
      #expect(try tower.change() == .createsList)
      #expect(try !tower.isAdded())

      try tower.add()

      #expect(try tower.isAdded())
      #expect(try tower.change() == nil)
      let entries = try list(of: tower)
      #expect(entries.count == 1)
      #expect(entries.first?["Identifier"] as? String == "seamerge")
      #expect(entries.first?["ApplicationIdentifier"] as? String == "app.eiden.seamerge")
      #expect(entries.first?["DisplayName"] as? String == "Seamerge")
      #expect(entries.first?["LaunchScript"] as? String == "seamerge.sh")
      #expect(entries.first?["SupportsMergeTool"] as? Bool == true)
      #expect(entries.first?["SupportsDiffChangeset"] as? Bool == false)
      let script = tower.folder.appending(path: "seamerge.sh").path
      #expect(FileManager.default.isExecutableFile(atPath: script))
    }
  }

  @Test func otherToolsOfTheListStayWhenAddingAndRemoving() throws {
    try withSandbox { sandbox in
      let tower = configuration(in: sandbox)
      let other: [[String: Any]] = [
        ["Identifier": "mytool", "DisplayName": "My Tool", "LaunchScript": "mytool.sh"]
      ]
      try FileManager.default.createDirectory(at: tower.folder, withIntermediateDirectories: true)
      try PropertyListSerialization.data(fromPropertyList: other, format: .xml, options: 0)
        .write(to: tower.folder.appending(path: "CompareTools.plist"))
      #expect(try tower.change() == .addsToList)

      try tower.add()
      #expect(
        try list(of: tower).compactMap { $0["Identifier"] as? String } == ["mytool", "seamerge"])
      try tower.remove()

      #expect(try list(of: tower).compactMap { $0["Identifier"] as? String } == ["mytool"])
      #expect(
        !FileManager.default.fileExists(atPath: tower.folder.appending(path: "seamerge.sh").path))
    }
  }

  @Test func removingTheOnlyEntryRemovesTheList() throws {
    try withSandbox { sandbox in
      let tower = configuration(in: sandbox)
      try tower.add()

      try tower.remove()

      let left = try FileManager.default.contentsOfDirectory(atPath: tower.folder.path)
      #expect(left.isEmpty)
    }
  }

  @Test func entryOfAnotherCopyIsReplaced() throws {
    try withSandbox { sandbox in
      let folder = TowerConfiguration.folder(inHome: sandbox.directory.appending(path: "home"))
      try TowerConfiguration(helper: URL(filePath: "/Volumes/Seamerge/seamerge"), folder: folder)
        .add()
      let tower = configuration(in: sandbox)
      #expect(try tower.change() == .replacesEntry)

      try tower.add()

      #expect(try tower.isAdded())
      #expect(try list(of: tower).count == 1)
    }
  }

  @Test func listThatIsNotAListOfToolsStaysUntouched() throws {
    try withSandbox { sandbox in
      let tower = configuration(in: sandbox)
      let listURL = tower.folder.appending(path: "CompareTools.plist")
      try FileManager.default.createDirectory(at: tower.folder, withIntermediateDirectories: true)
      try Data("not a list".utf8).write(to: listURL)

      #expect(throws: TowerConfigurationError.self) { try tower.add() }
      #expect(throws: TowerConfigurationError.self) { try tower.remove() }

      #expect(try String(contentsOf: listURL, encoding: .utf8) == "not a list")
    }
  }

  /// Runs the script with the arguments Tower passes, with a helper in a folder that needs
  /// quoting, which records its arguments.
  @Test(arguments: [
    (["LOCAL", "REMOTE"], ["diff", "--", "LOCAL", "REMOTE"]),
    (
      ["LOCAL", "REMOTE", "src/a.swift"],
      ["diff", "--path", "src/a.swift", "--", "LOCAL", "REMOTE"]
    ),
    (
      ["LOCAL", "REMOTE", "BASE", "MERGED"],
      [
        "merge", "--from-git", "--base", "BASE", "--local", "LOCAL", "--remote", "REMOTE",
        "--output", "MERGED",
      ]
    ),
  ])
  func scriptHandsTheFilesToTheHelper(arguments: [String], expected: [String]) throws {
    try withSandbox { sandbox in
      let helper = try sandbox.makeExecutable(
        "seamerge", in: "It's Seamerge",
        script: #"printf '%s\n' "$@" > "$(dirname "$0")/arguments"; exit 7"#)
      let tower = TowerConfiguration(
        helper: helper,
        folder: TowerConfiguration.folder(inHome: sandbox.directory.appending(path: "home")))
      try tower.add()

      let result = try runProcess(
        tower.folder.appending(path: "seamerge.sh"), arguments: arguments,
        environment: sandbox.environment)

      #expect(result.status == 7)
      let recorded = try String(
        contentsOf: helper.deletingLastPathComponent().appending(path: "arguments"), encoding: .utf8
      )
      #expect(recorded.split(separator: "\n").map(String.init) == expected)
    }
  }

  /// Runs the script as Tower runs a merge tool, through `git mergetool` with the command and
  /// `trustExitCode` Tower sets, with a helper that saves or cancels.
  @Test(arguments: [true, false])
  func mergeFromTowerIsResolvedOnlyWhenTheHelperSaves(saves: Bool) throws {
    try withSandbox { sandbox in
      let repository = try sandbox.makeRepository("merge")
      // The helper gets the output file as tenth argument: merge --from-git --base … --output.
      let helper = try sandbox.makeExecutable(
        "seamerge", in: "app",
        script: saves ? #"printf 'merged\n' > "${10}"; exit 0"# : "exit 1")
      let tower = TowerConfiguration(
        helper: helper,
        folder: TowerConfiguration.folder(inHome: sandbox.directory.appending(path: "home")))
      try tower.add()
      let script = tower.folder.appending(path: "seamerge.sh").path
      let git = sandbox.git()

      // `git mergetool` itself fails when the tool does, as Tower sees it.
      do {
        _ = try git.run(
          [
            "-c", #"mergetool.tower.cmd="\#(script)" "$LOCAL" "$REMOTE" "$BASE" "$MERGED""#,
            "-c", "mergetool.tower.trustExitCode=true", "mergetool", "-y", "-t", "tower",
          ], in: repository)
        #expect(saves)
      } catch {
        #expect(!saves, "\(error)")
      }

      let unmerged = try git.output(["diff", "--name-only", "--diff-filter=U"], in: repository)
      #expect(unmerged.isEmpty == saves, "\(unmerged)")
    }
  }

  private func configuration(in sandbox: Sandbox) -> TowerConfiguration {
    TowerConfiguration(
      helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
      folder: TowerConfiguration.folder(inHome: sandbox.directory.appending(path: "home")))
  }

  private func list(of tower: TowerConfiguration) throws -> [[String: Any]] {
    let data = try Data(contentsOf: tower.folder.appending(path: "CompareTools.plist"))
    return try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])
  }
}
