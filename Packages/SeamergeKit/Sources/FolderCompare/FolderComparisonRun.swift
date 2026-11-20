import CoreServices
import Foundation

/// Compares two folders away from the main thread for the collection that shows them, and keeps
/// comparing what changes in them afterwards.
///
/// The run first pairs every entry and hands over at once what the sizes tell; then it compares
/// the contents of the files of the same size, a batch at a time. Once every file is compared,
/// it watches both folders and compares each entry that changes anew.
@MainActor
final class FolderComparisonRun {
  /// What the run found.
  enum Event: Sendable {
    /// Every entry is paired: `files` are those whose change shows without reading them, and
    /// `waiting` files wait for their contents to be compared.
    case listed([CollectedFile], waiting: Int)

    /// The contents of `files` were compared.
    case compared([CollectedFile])

    /// Every file is compared.
    case finished

    /// Entries changed on disk; `files` are all files of the folders now.
    case replaced([CollectedFile])
  }

  /// Compares the folders.
  let comparer: FolderComparer

  private let onEvent: (Event) -> Void
  private let files: () -> [CollectedFile]
  private let latency: Duration
  private var comparison: Task<Void, Never>?
  private var watcher: FolderWatcher?
  private var changes: [FolderWatcher.Change] = []
  private var comparesEverythingAgain = false
  private var rescan: Task<Void, Never>?

  /// The most files the run hands over at once while it compares contents, and the longest it
  /// waits before it hands over those it has.
  private nonisolated static let batchSize = 1000
  private nonisolated static let batchInterval = Duration.milliseconds(100)

  /// The most changes on disk the run keeps apart; beyond that, it compares everything again,
  /// which costs less than finding out what so many changes touch.
  nonisolated static let changeLimit = 5000

  /// Creates a run that compares with `comparer`, tells `onEvent` on the main actor what it
  /// found, and gathers the changes on disk of every `latency` before it compares them; `files`
  /// gives the files found so far, which those changes replace in part.
  init(
    comparer: FolderComparer, latency: Duration = .milliseconds(300),
    files: @escaping () -> [CollectedFile], onEvent: @escaping (Event) -> Void
  ) {
    self.comparer = comparer
    self.latency = latency
    self.files = files
    self.onEvent = onEvent
  }

  /// Compares the folders, then watches them; once only.
  func start() {
    guard comparison == nil else { return }
    // Changes from now on are reported once the watcher starts, also those made while the
    // entries are read.
    let since = FolderWatcher.currentEvent
    let comparer = comparer
    let (events, continuation) = AsyncStream.makeStream(of: Event.self)
    let work = Task { await Self.compareAll(with: comparer, into: continuation) }
    continuation.onTermination = { _ in work.cancel() }
    comparison = Task { [weak self] in
      for await event in events {
        self?.onEvent(event)
      }
      guard !Task.isCancelled else { return }
      self?.watch(since: since)
    }
  }

  /// Stops comparing and watching.
  func stop() {
    comparison?.cancel()
    rescan?.cancel()
    watcher = nil
  }

  /// Waits until every file is compared once, or the run stopped.
  func waitUntilCompared() async {
    await comparison?.value
  }

  private func watch(since: FSEventStreamEventId) {
    let roots = comparer.roots
    watcher = FolderWatcher(paths: [roots.left, roots.right], since: since, latency: latency) {
      [weak self] changes in
      self?.foldersDidChange(changes)
    }
  }

  /// Takes in `changes` on disk and compares them once no comparison of changes runs; beyond
  /// ``changeLimit`` waiting changes, everything is compared again.
  func foldersDidChange(_ changes: [FolderWatcher.Change]) {
    if !comparesEverythingAgain {
      self.changes += changes
      if self.changes.count > Self.changeLimit {
        self.changes = []
        comparesEverythingAgain = true
      }
    }
    if rescan == nil {
      compareChanges()
    }
  }

  /// Compares anew, away from the main thread, what changed on disk, and again afterwards if
  /// more changed meanwhile.
  private func compareChanges() {
    guard !changes.isEmpty || comparesEverythingAgain else { return }
    let (changes, everything) = (self.changes, comparesEverythingAgain)
    self.changes = []
    comparesEverythingAgain = false
    let (comparer, files) = (comparer, files())
    rescan = Task { [weak self] in
      let replaced = await Self.files(
        afterChanges: everything ? nil : changes, to: files, with: comparer)
      guard let self, !Task.isCancelled else { return }
      if let replaced {
        onEvent(.replaced(replaced))
      }
      rescan = nil
      compareChanges()
    }
  }

  /// `files` once the entries that `changes` touch, or every entry for `nil`, are compared anew;
  /// `nil` if the changes touch nothing the comparison looks at.
  @concurrent
  private static func files(
    afterChanges changes: [FolderWatcher.Change]?, to files: [CollectedFile],
    with comparer: FolderComparer
  ) async -> [CollectedFile]? {
    let paths = changes.map { changedPaths($0, with: comparer) } ?? [""]
    guard !paths.isEmpty else { return nil }
    let keys = Set(paths.map(comparer.key(of:)))
    let compared = paths.flatMap { path in
      comparer.pairs(at: path).map { comparer.file(for: $0, change: comparer.change(of: $0)) }
    }.sorted { $0.precedes($1) }
    let kept = keys.contains("") ? [] : files.filter { !lies(comparer.key(of: $0.path), in: keys) }
    return FileCollection.merging(compared, into: kept)
  }

  /// The paths relative to the tops of the folders that `changes` touch, without those that lie
  /// below another of them and without those the comparison leaves out.
  private nonisolated static func changedPaths(
    _ changes: [FolderWatcher.Change], with comparer: FolderComparer
  ) -> [String] {
    let roots = comparer.roots
    var candidates: [(path: String, key: String)] = []
    for change in changes where !change.isFolderAlone {
      guard
        let path = path(change.path, in: roots.left) ?? path(change.path, in: roots.right),
        !path.split(separator: "/").contains(where: {
          FolderListing.skippedNames.contains(String($0))
        })
      else { continue }
      candidates.append((path, comparer.key(of: path)))
    }
    // Shorter paths first, so that a folder is kept before what lies below it.
    candidates.sort { $0.key.count < $1.key.count }
    var keys: Set<String> = []
    var paths: [String] = []
    for candidate in candidates where !lies(candidate.key, in: keys) {
      keys.insert(candidate.key)
      paths.append(candidate.path)
    }
    return paths
  }

  /// Whether the path of `key` is one of `keys` or lies below one of them.
  private nonisolated static func lies(_ key: String, in keys: Set<String>) -> Bool {
    if keys.contains("") || keys.contains(key) {
      return true
    }
    var prefix = key[...]
    while let slash = prefix.lastIndex(of: "/") {
      prefix = prefix[..<slash]
      if keys.contains(String(prefix)) {
        return true
      }
    }
    return false
  }

  /// `path` relative to `root`, or `nil` if it does not lie in it.
  private nonisolated static func path(_ path: String, in root: String) -> String? {
    if path == root { return "" }
    guard path.hasPrefix(root + "/") else { return nil }
    return String(path.dropFirst(root.count + 1))
  }

  /// Pairs every entry, hands over what shows without reading, then compares the contents of
  /// the rest a batch at a time, until done or cancelled.
  @concurrent
  private static func compareAll(
    with comparer: FolderComparer, into continuation: AsyncStream<Event>.Continuation
  ) async {
    defer { continuation.finish() }
    var known: [CollectedFile] = []
    var waiting: [FolderComparer.Pair] = []
    for pair in comparer.pairs(at: "") {
      if let change = comparer.change(withoutReading: pair) {
        known.append(comparer.file(for: pair, change: change))
      } else {
        waiting.append(pair)
      }
    }
    continuation.yield(.listed(known, waiting: waiting.count))
    var batch: [CollectedFile] = []
    var batchStart = ContinuousClock.now
    for pair in waiting {
      guard !Task.isCancelled else { return }
      batch.append(comparer.file(for: pair, change: comparer.change(of: pair)))
      if batch.count >= batchSize || batchStart.duration(to: .now) >= batchInterval {
        continuation.yield(.compared(batch))
        batch = []
        batchStart = .now
      }
    }
    if !batch.isEmpty {
      continuation.yield(.compared(batch))
    }
    continuation.yield(.finished)
  }
}
