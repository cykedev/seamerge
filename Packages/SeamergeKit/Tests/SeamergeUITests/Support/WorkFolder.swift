import Darwin
import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

/// A folder of work of merges for one test, removed when the test ends, with a timer that the
/// test fires by hand and a clock that stands still unless the test moves it.
@MainActor
final class WorkFolder {
  /// The time the folder and its keepers start at.
  nonisolated static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  let url: URL
  let store: MergeWorkStore
  let timer = ManualWorkTimer()

  /// The time the keepers of the folder date their work by.
  var now = WorkFolder.start

  init() {
    url = Self.processFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    store = MergeWorkStore(folder: url, now: { WorkFolder.start })
  }

  /// The folder of the folders of work of this test process, removed when the process exits,
  /// whatever the outcome of its tests, together with the folder above once it is empty.
  ///
  /// Folders of processes that ended otherwise, such as by a crash, go when the next process
  /// makes its first folder of work.
  ///
  /// A folder of work removes itself at the end of its test, but a write that the test did not
  /// wait for could make it anew.
  nonisolated private static let processFolder: URL = {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "SeamergeUITests-WorkFolders", directoryHint: .isDirectory)
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    } catch {
      names = []
    }
    for name in names {
      guard let pid = Int32(name), pid != getpid(), kill(pid, 0) != 0, errno == ESRCH else {
        continue
      }
      removeFolder(root.appending(path: name))
    }
    atexit {
      WorkFolder.removeFolder(WorkFolder.processFolder)
      // Only an empty folder goes; another process may still use it.
      _ = rmdir(WorkFolder.processFolder.deletingLastPathComponent().path)
    }
    return root.appending(path: "\(getpid())", directoryHint: .isDirectory)
  }()

  /// Removes the folder at `url` if it is there.
  nonisolated private static func removeFolder(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      FileHandle.standardError.write(Data("Could not remove \(url.path): \(error)\n".utf8))
    }
  }

  isolated deinit {
    Self.removeFolder(url)
  }

  /// A keeper that writes to the folder at the pace of the timer, dated by ``now``.
  func keeper() -> MergeWorkKeeper {
    MergeWorkKeeper(store: store, timer: timer, now: { [unowned self] in now })
  }

  /// The work kept for the merge of `inputs`, or `nil` if there is none.
  func work(of inputs: Session.Inputs<SourceFile>) async throws -> MergeWork? {
    try await store.read(MergeKey(inputs))
  }

  /// The names of the files in the folder.
  var fileNames: [String] {
    get throws {
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
  }
}

/// A timer that fires only when the test says so, and remembers what it was asked to wait.
@MainActor
final class ManualWorkTimer: WorkTimer {
  private var actions: [@MainActor () -> Void] = []

  /// The delays asked for, in order.
  private(set) var delays: [Duration] = []

  /// Whether an action waits for the timer.
  var isScheduled: Bool { !actions.isEmpty }

  func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
    delays.append(delay)
    actions.append(action)
  }

  /// Runs every action that waits, as if their time had come.
  func fire() {
    let due = actions
    actions = []
    for action in due {
      action()
    }
  }
}
