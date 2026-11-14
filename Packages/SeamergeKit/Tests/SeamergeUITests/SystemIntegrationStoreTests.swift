import Foundation
import GitSupport
import Testing

@testable import SeamergeUI

/// The settings of a Mac of its own: a copy of the app, a global Git configuration, Tower's
/// folder of tools and user defaults, all in a temporary folder.
@Suite(.timeLimit(.minutes(1))) struct SystemIntegrationStoreTests {
  @Test func setUpAndRemoveLeaveGitAndTowerAsTheyWere() async throws {
    let mac = try TemporaryMac()
    defer { mac.remove() }
    try mac.writeGitConfiguration("[merge]\n\ttool = Kaleidoscope\n[diff]\n\ttool = Kaleidoscope\n")
    let before = try mac.gitConfiguration()
    let store = try mac.store()

    let offer = try await store.status()
    #expect(offer.gitState?.merge == .other("Kaleidoscope"))
    #expect(offer.tower == .notAdded(.createsList))
    #expect(offer.backup == nil)
    #expect(offer.problem == nil)

    try await store.setUp(addingToTower: true)
    let setUp = try await mac.store().status()
    #expect(setUp.isSetUp)
    #expect(setUp.tower == .added)
    #expect(setUp.backup?.restoredTools.merge == "Kaleidoscope")

    try await store.remove()
    #expect(try mac.gitConfiguration() == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: mac.towerFolder.path).isEmpty)
    #expect(try await store.status().backup == nil)
  }

  @Test func failedSetupOfGitPutsTheEarlierTowerEntryBack() async throws {
    let mac = try TemporaryMac()
    defer { mac.remove() }
    try TowerConfiguration(
      helper: URL(filePath: "/Volumes/Seamerge/Seamerge.app/Contents/Helpers/seamerge"),
      folder: mac.towerFolder
    ).add()
    let before = try mac.towerFiles()
    let store = try mac.store(failingOn: "--replace-all diff.tool ")
    #expect(try await store.status().tower == .notAdded(.replacesEntry))

    await #expect(throws: IntegrationFailure.self) { try await store.setUp(addingToTower: true) }

    #expect(try mac.towerFiles() == before)
  }

  @Test func addingToTowerLeavesGitAlone() async throws {
    let mac = try TemporaryMac()
    defer { mac.remove() }
    let before = try mac.gitConfiguration()
    let store = try mac.store()

    try await store.addToTower()

    #expect(try await store.status().tower == .added)
    #expect(try mac.gitConfiguration() == before)
  }

  @Test func failedSetupOfGitTakesSeamergeOutOfTowerAgain() async throws {
    let mac = try TemporaryMac()
    defer { mac.remove() }
    let before = try mac.gitConfiguration()
    let store = try mac.store(failingOn: "--replace-all diff.tool ")

    await #expect(throws: IntegrationFailure.self) { try await store.setUp(addingToTower: true) }

    #expect(try mac.gitConfiguration() == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: mac.towerFolder.path).isEmpty)
    #expect(try await store.status().backup == nil)
  }
}

/// A temporary folder that stands in for a Mac: a home folder with a Git configuration, Tower's
/// folder of tools, and a copy of the app with its helper.
private struct TemporaryMac {
  let folder = FileManager.default.temporaryDirectory
    .appending(path: "SystemIntegrationStore-\(UUID().uuidString)", directoryHint: .isDirectory)
  let defaultsSuite = "app.eiden.seamerge.tests.\(UUID().uuidString)"

  var home: URL { folder.appending(path: "home") }
  var bundle: URL { folder.appending(path: "Applications/Seamerge.app") }
  var towerFolder: URL { TowerConfiguration.folder(inHome: home) }
  var gitConfigurationFile: URL { home.appending(path: ".gitconfig") }

  var environment: [String: String] {
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["HOME"] = home.path
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = gitConfigurationFile.path
    return environment
  }

  init() throws {
    try FileManager.default.createDirectory(at: towerFolder, withIntermediateDirectories: true)
    try writeExecutable(at: AppLocation.helper(inBundle: bundle), script: "exit 0")
    try Data().write(to: gitConfigurationFile)
  }

  /// The store of this Mac; with `failingOn`, its `git` refuses every command that contains it.
  func store(failingOn refused: String? = nil) throws -> SystemIntegrationStore {
    var environment = environment
    if let refused {
      let git = try #require(Git.installed(environment: environment))
      let failing = folder.appending(path: "bin/git")
      try writeExecutable(
        at: failing,
        script: """
          case "$*" in *"\(refused)"*) echo "error: cannot lock" >&2; exit 255;; esac
          exec '\(git.executableURL.path)' "$@"
          """)
      let path = environment["PATH"] ?? ""
      environment["PATH"] = failing.deletingLastPathComponent().path + ":" + path
    }
    return SystemIntegrationStore(
      bundle: bundle, environment: environment, towerFolder: towerFolder,
      defaultsSuite: defaultsSuite)
  }

  /// The files in Tower's folder of tools with their contents.
  func towerFiles() throws -> [String: Data] {
    var files: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: towerFolder.path) {
      files[name] = try Data(contentsOf: towerFolder.appending(path: name))
    }
    return files
  }

  func writeGitConfiguration(_ text: String) throws {
    try Data(text.utf8).write(to: gitConfigurationFile)
  }

  /// The entries of the global Git configuration, in the order of their keys.
  func gitConfiguration() throws -> [String] {
    let git = try #require(Git.installed(environment: environment))
    do {
      let list = String(decoding: try git.run(["config", "--global", "--list"]), as: UTF8.self)
      return list.split(separator: "\n").map(String.init).sorted()
    } catch .failed(_, status: 1, _) {
      return []
    }
  }

  func remove() {
    UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) }
  }

  private func writeExecutable(at url: URL, script: String) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n\(script)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
}
