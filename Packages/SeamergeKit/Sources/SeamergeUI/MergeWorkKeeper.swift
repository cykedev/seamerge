import Foundation
import MergeModel
import os

/// Keeps the work of a merge window on disk while the window is open, so that the same merge
/// opened again finds it, also after a crash.
///
/// The window tells the keeper of every step that changes the work; the keeper captures it a
/// second later at the latest, and at most once a second, however fast the steps come. Closing
/// the window keeps the work at once, or removes it once the merge is finished. The main actor
/// only takes a snapshot of values; capturing, encoding and writing run in the background, one
/// write after another, in the order the window took the snapshots.
///
/// The keeper removes only work it knows to be there: work it wrote or that the window restored.
/// A file it cannot read, or one of another format version, stays for the store to expire.
@MainActor
final class MergeWorkKeeper {
  /// The least time between two captures, which is also the most time a step waits for one.
  static let interval: Duration = .seconds(1)

  /// The folder that holds the work.
  let store: MergeWorkStore

  /// The time now, which dates the work and tells whether it is from today.
  let now: () -> Date

  /// Takes the snapshot of the work in the window, or `nil` while the window shows no result
  /// whose work it keeps, such as while it waits for its comparison.
  var snapshot: () -> WorkSnapshot? = { nil }

  private let timer: any WorkTimer

  /// The key of the merge in the window, worked out away from the main actor; `nil` until the
  /// window shows the lines of its merge.
  private var key: Task<MergeKey, Never>?

  /// Whether the timer runs towards a capture.
  private var isScheduled = false

  /// Whether a step changed the work since it was last captured.
  private var hasChanges = false

  /// Whether the folder may hold work of the merge that the keeper wrote or the window restored.
  private var mayHoldWork = false

  /// The last write or removal handed to the background while it runs, which the next one waits
  /// for; it ends once every write and removal before has ended.
  private(set) var lastOperation: Task<Void, Never>?

  /// The number of writes and removals handed to the background so far, which tells whether
  /// one that ends is the last.
  private var operationCount = 0

  nonisolated private static let logger = Logger(
    subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Creates a keeper that writes to `store` at the pace of `timer`, dating the work by `now`.
  init(
    store: MergeWorkStore, timer: any WorkTimer = RunLoopWorkTimer(),
    now: @escaping () -> Date = { Date() }
  ) {
    self.store = store
    self.timer = timer
    self.now = now
  }

  /// Keeps the work under the key of `inputs`, the files the window now merges, which it works
  /// out in the background.
  ///
  /// Work kept under an earlier key stays: it belongs to a merge of other files.
  func keepWork(of inputs: Session.Inputs<SourceFile>) {
    key = Task.detached(priority: .utility) { MergeKey(inputs) }
    mayHoldWork = false
  }

  /// Keeps the work under the key that `earlierWork` found when the window opened; the folder
  /// holds work of the merge if it found some.
  func keepWork(as earlierWork: EarlierWork) {
    let key = earlierWork.key
    self.key = Task { key }
    mayHoldWork = earlierWork.work != nil
  }

  /// Notes that a step changed the work, which the keeper captures a second later at the latest.
  func workDidChange() {
    hasChanges = true
    guard !isScheduled else { return }
    isScheduled = true
    timer.schedule(after: Self.interval) { [weak self] in
      guard let self else { return }
      isScheduled = false
      if hasChanges {
        keepNow()
      }
    }
  }

  /// Captures the work now and writes it in the background, or removes the work the folder holds
  /// once nothing is left to keep, as after resetting every decision.
  ///
  /// - Returns: The task that ends once the work is written, together with every write before,
  ///   or `nil` if nothing is being written.
  @discardableResult
  func keepNow() -> Task<Void, Never>? {
    hasChanges = false
    guard let key, let snapshot = snapshot() else { return lastOperation }
    if snapshot.document.canResetAll {
      mayHoldWork = true
      return enqueue { store in await Self.write(snapshot, key: key, to: store) }
    }
    return removeKnownWork(key: key)
  }

  /// Removes the work of the merge, which is finished, and stops keeping it.
  ///
  /// - Returns: The task that ends once the work is removed, together with every write before,
  ///   or `nil` if nothing is being written or removed.
  @discardableResult
  func removeWork() -> Task<Void, Never>? {
    hasChanges = false
    guard let key else { return lastOperation }
    self.key = nil
    return removeKnownWork(key: key)
  }

  /// Removes the work of the merge with `key` if the folder may hold work the keeper knows.
  private func removeKnownWork(key: Task<MergeKey, Never>) -> Task<Void, Never>? {
    guard mayHoldWork else { return lastOperation }
    mayHoldWork = false
    return enqueue { store in await Self.remove(key, from: store) }
  }

  /// Runs `operation` in the background once every operation before has ended.
  private func enqueue(
    _ operation: @escaping @Sendable (MergeWorkStore) async -> Void
  ) -> Task<Void, Never> {
    let previous = lastOperation
    let store = store
    operationCount += 1
    let number = operationCount
    let operation = Task { [weak self] in
      await previous?.value
      await operation(store)
      if let self, operationCount == number {
        lastOperation = nil
      }
    }
    lastOperation = operation
    return operation
  }

  /// Captures the work of `snapshot` and writes it under `key`.
  @concurrent
  private static func write(
    _ snapshot: WorkSnapshot, key: Task<MergeKey, Never>, to store: MergeWorkStore
  ) async {
    guard
      let work = MergeWork(
        capturing: snapshot.document, text: snapshot.text, key: await key.value,
        format: snapshot.format, currentBlock: snapshot.currentBlock, savedAt: snapshot.savedAt)
    else { return }
    do {
      try await store.write(work)
    } catch {
      // The store has logged it. The window works on without its work kept; a note in the
      // middle of a merge would do more harm than the missing work.
    }
  }

  /// Removes the work kept under `key`.
  @concurrent
  private static func remove(_ key: Task<MergeKey, Never>, from store: MergeWorkStore) async {
    do {
      try await store.remove(key.value)
    } catch {
      // The store has logged it; the work expires in time.
    }
  }

  /// The key of a merge of `inputs` and the work the store holds for it, if any.
  ///
  /// Work that cannot be read counts as none and stays where it is.
  @concurrent
  static func earlierWork(
    of inputs: Session.Inputs<SourceFile>, in store: MergeWorkStore
  ) async -> EarlierWork {
    let key = MergeKey(inputs)
    do {
      return EarlierWork(key: key, work: try await store.read(key))
    } catch {
      logger.error(
        "Cannot read the work of a merge: \(String(describing: error), privacy: .public)")
      return EarlierWork(key: key, work: nil)
    }
  }
}

/// The work in a merge window as the main actor hands it to the background: values, taken in an
/// instant, whatever the size of the result.
struct WorkSnapshot: Sendable {
  /// The result of the merge.
  let document: ResultDocument

  /// The text of the result, as long as the segments of ``document`` together.
  let text: String

  /// The format the result is written in.
  let format: ResultFormat

  /// The block the cursor is in, if any.
  let currentBlock: Block?

  /// When the snapshot was taken.
  let savedAt: Date
}

/// What the folder of work holds for a merge as its window opens.
struct EarlierWork: Sendable {
  /// The key of the merge.
  let key: MergeKey

  /// The work kept for the merge, or `nil` if there is none that this version can read.
  let work: MergeWork?
}
