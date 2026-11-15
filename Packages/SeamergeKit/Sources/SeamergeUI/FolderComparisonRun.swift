import Foundation

/// Compares two folders away from the main thread for the collection that shows them.
///
/// The run first pairs every entry and hands over at once what the sizes tell; then it compares
/// the contents of the files of the same size, a batch at a time.
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
  }

  /// Compares the folders.
  let comparer: FolderComparer

  private let onEvent: (Event) -> Void
  private var comparison: Task<Void, Never>?

  /// The most files the run hands over at once while it compares contents, and the longest it
  /// waits before it hands over those it has.
  private nonisolated static let batchSize = 1000
  private nonisolated static let batchInterval = Duration.milliseconds(100)

  /// Creates a run that compares with `comparer` and tells `onEvent` on the main actor what it
  /// found.
  init(comparer: FolderComparer, onEvent: @escaping (Event) -> Void) {
    self.comparer = comparer
    self.onEvent = onEvent
  }

  /// Compares the folders; once only.
  func start() {
    guard comparison == nil else { return }
    let comparer = comparer
    let (events, continuation) = AsyncStream.makeStream(of: Event.self)
    let work = Task { await Self.compareAll(with: comparer, into: continuation) }
    continuation.onTermination = { _ in work.cancel() }
    comparison = Task { [weak self] in
      for await event in events {
        self?.onEvent(event)
      }
    }
  }

  /// Stops comparing.
  func stop() {
    comparison?.cancel()
  }

  /// Waits until every file is compared once, or the run stopped.
  func waitUntilCompared() async {
    await comparison?.value
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
