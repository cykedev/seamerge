import AppKit
import GitSupport
import Testing

@testable import SeamergeUI

/// Settings of Git and Tower that answer as the test says and record what they were asked to
/// write.
actor IntegrationStoreRecorder: IntegrationStore {
  /// What reading the settings returns; setting up and removing change it as the real ones would.
  var current: IntegrationStatus

  /// The failure of the next write, if it should fail.
  var failure: IntegrationFailure?

  /// The writes so far: `setUp` with whether Tower was added, or `remove`.
  private(set) var writes: [String] = []

  init(_ status: IntegrationStatus) {
    current = status
  }

  func fail(with failure: IntegrationFailure?) {
    self.failure = failure
  }

  func status() async throws(IntegrationFailure) -> IntegrationStatus {
    current
  }

  func setUp(addingToTower: Bool) async throws(IntegrationFailure) {
    writes.append("setUp(addingToTower: \(addingToTower))")
    if let failure { throw failure }
    current.git = .installed(
      GitIntegrationState(merge: .seamerge, diff: .seamerge, changedSwitches: []))
    if addingToTower { current.tower = .added }
  }

  func addToTower() async throws(IntegrationFailure) {
    writes.append("addToTower")
    if let failure { throw failure }
    current.tower = .added
  }

  func remove() async throws(IntegrationFailure) {
    writes.append("remove")
    if let failure { throw failure }
    current.git = .installed(GitIntegrationState(merge: .none, diff: .none, changedSwitches: []))
  }
}

extension IntegrationStatus {
  /// A status of Git with `merge` and `diff`, the switches still on, and nothing else.
  static func git(
    merge: GitIntegrationState.Tool, diff: GitIntegrationState.Tool,
    switches: Set<GitIntegrationState.Switch> = [.prompt, .keepBackup],
    tower: TowerStatus? = nil, backup: GitBackup? = nil, problem: AppLocation.Problem? = nil
  ) -> IntegrationStatus {
    IntegrationStatus(
      git: .installed(GitIntegrationState(merge: merge, diff: diff, changedSwitches: switches)),
      tower: tower, backup: backup, problem: problem,
      commands: GitConfiguration(
        helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge")
      ).commands)
  }

  /// Git as on most Macs that used another tool: Kaleidoscope for both, the switches on.
  static let kaleidoscope = git(merge: .other("Kaleidoscope"), diff: .other("Kaleidoscope"))

  /// Git using this copy for both, after a setup that replaced Kaleidoscope.
  static let setUp = git(
    merge: .seamerge, diff: .seamerge, switches: [],
    backup: GitBackup(values: ["merge.tool": "Kaleidoscope", "diff.tool": "Kaleidoscope"]))
}

/// A window Compare Files whose settings of Git come from `store`.
@MainActor
func integrationFixture(
  _ status: IntegrationStatus, displayOptions: DisplayOptions = DisplayOptions()
) throws -> (fixture: CompareFilesFixture, store: IntegrationStoreRecorder) {
  let store = IntegrationStoreRecorder(status)
  return (try CompareFilesFixture(displayOptions: displayOptions, integrationStore: store), store)
}
