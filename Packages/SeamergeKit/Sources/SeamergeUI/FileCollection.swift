import Foundation
import GitSupport

/// The files that the calls of one origin hand over to one window, in the order of the run.
///
/// A collection receives files while calls of its origin may still come: with the numbers that
/// Git gives, until every number up to the count is there or the run of Git ends; without them,
/// or without the run, also until a quiet period has passed since the last file. The window that shows the files may close
/// first; the collection is then dismissed, and the calls that still come find it so.
@MainActor
public final class FileCollection {
  /// The origin of the calls, or `nil` for the files of a comparison of two folders.
  public let origin: CollectionOrigin?

  /// The files, in the order of Git where it numbers them, else by path.
  public private(set) var files: [CollectedFile] = []

  /// How many files the run hands over, if Git tells.
  public let expectedCount: Int?

  /// Whether files may still come.
  public private(set) var isReceiving: Bool

  /// Whether the window of the collection has closed.
  public private(set) var isDismissed = false

  /// Learns of every change: a file that came, at its index, or the end of receiving.
  var onChange: ((Change) -> Void)?

  /// A change of a collection.
  enum Change: Equatable {
    /// A file came and stands at the index.
    case inserted(Int)

    /// No more files come.
    case complete
  }

  private let quietPeriod: Duration
  private var quietTimer: Timer?
  private var runSource: (any DispatchSourceProcess)?

  /// Creates a collection that receives the files of the calls of `origin`, of which Git hands
  /// over `expectedCount`, if it tells.
  ///
  /// Without a count or without a run in `origin`, receiving ends `quietPeriod` after the last
  /// file; with a run, it ends when that process ends.
  public init(origin: CollectionOrigin, expectedCount: Int?, quietPeriod: Duration = .seconds(3)) {
    self.origin = origin
    self.expectedCount = expectedCount
    self.quietPeriod = quietPeriod
    isReceiving = true
    if let run = origin.run {
      watch(run)
    }
  }

  /// Creates a collection of `files` that are all there.
  public init(files: [CollectedFile]) {
    origin = nil
    expectedCount = files.count
    quietPeriod = .zero
    isReceiving = false
    self.files = files.sorted { $0.precedes($1) }
  }

  /// Whether a call of `origin` belongs to this collection: it comes from the same origin while
  /// files may still come.
  public func accepts(_ origin: CollectionOrigin) -> Bool {
    isReceiving && origin == self.origin
  }

  /// Adds `file` at its place in the order, and ends receiving once every number Git announced
  /// is there.
  ///
  /// A call that joined the collection while it received files adds its file even if receiving
  /// ended meanwhile, as it does while the call copies the file.
  ///
  /// - Precondition: The window of the collection has not closed.
  public func add(_ file: CollectedFile) {
    precondition(!isDismissed, "A collection takes no files once its window has closed")
    let index = files.firstIndex { file.precedes($0) } ?? files.endIndex
    files.insert(file, at: index)
    onChange?(.inserted(index))
    guard isReceiving else { return }
    if let expectedCount, Set(files.compactMap(\.number)).count >= expectedCount {
      endReceiving()
    } else {
      restartQuietPeriod()
    }
  }

  /// Ends receiving: calls of the origin that still come belong to a new collection.
  public func endReceiving() {
    guard isReceiving else { return }
    isReceiving = false
    quietTimer?.invalidate()
    quietTimer = nil
    runSource?.cancel()
    runSource = nil
    onChange?(.complete)
  }

  /// Notes that the window of the collection closed.
  public func dismiss() {
    isDismissed = true
    onChange = nil
  }

  private func restartQuietPeriod() {
    // Without the run to watch, a run that stopped early would leave the collection receiving
    // for good, and every later call of the origin would find it.
    guard isReceiving, expectedCount == nil || origin?.run == nil else { return }
    quietTimer?.invalidate()
    let interval =
      TimeInterval(quietPeriod.components.seconds)
      + TimeInterval(quietPeriod.components.attoseconds) / 1e18
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated { self?.endReceiving() }
    }
    RunLoop.main.add(timer, forMode: .common)
    quietTimer = timer
  }

  /// Ends receiving when the process of `run` ends, or at once if it no longer runs.
  private func watch(_ run: ProcessRun) {
    let source = DispatchSource.makeProcessSource(
      identifier: run.processID, eventMask: .exit, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.endReceiving() }
    }
    source.activate()
    runSource = source
    // The process may have ended before the source watched it.
    if !run.isRunning {
      endReceiving()
    }
  }
}
