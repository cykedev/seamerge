public import Foundation
import GitSupport

/// The files that one window compares: those that the calls of one origin hand over, in the
/// order of the run, or those of two folders, by path.
///
/// A collection receives files while calls of its origin may still come: with the numbers that
/// Git gives, until every number up to the count is there or the run of Git ends; without them,
/// or without the run, also until a quiet period has passed since the last file. The window that
/// shows the files may close first; the collection is then dismissed, and the calls that still
/// come find it so.
///
/// A collection of two folders receives files while it compares them, and afterwards follows
/// what changes in them until it is dismissed.
@MainActor
public final class FileCollection {
  /// The origin of the calls, or `nil` for the files of a comparison of two folders.
  public let origin: CollectionOrigin?

  /// The folders whose files the collection compares, or `nil` for the files of calls.
  public let folders: FolderPair?

  /// Whether the folders are those of `git difftool --dir-diff`, whose files Git names.
  let isFromGit: Bool

  /// The folders whose names tell the sides of a file apart, or `nil` where Git names the sides:
  /// for the files of calls, and for the folders of `git difftool --dir-diff`.
  package var namingFolders: FolderPair? {
    isFromGit ? nil : folders
  }

  /// The files, in the order of Git where it numbers them, else by path.
  public private(set) var files: [CollectedFile] = []

  /// How many files the run hands over, if Git tells.
  public let expectedCount: Int?

  /// Whether files may still come.
  public private(set) var isReceiving: Bool

  /// Whether the window of the collection has closed.
  public private(set) var isDismissed = false

  /// How many files of two folders are compared, while the collection compares them.
  public private(set) var comparedCount = 0

  /// How many files the two folders hold together, once every entry is paired.
  public private(set) var pairedCount: Int?

  /// Learns of every change: a file that came, at its index, files of folders that were compared
  /// or changed on disk, or the end of receiving.
  package var onChange: ((Change) -> Void)?

  /// A change of a collection.
  package enum Change: Equatable {
    /// A file came and stands at the index.
    case inserted(Int)

    /// Files of folders came, changed or went.
    case updated

    /// No more files come.
    case complete
  }

  private let quietPeriod: Duration
  private var quietTimer: Timer?
  private var runSource: (any DispatchSourceProcess)?
  private var folderRun: FolderComparisonRun?

  /// Creates a collection that receives the files of the calls of `origin`, of which Git hands
  /// over `expectedCount`, if it tells.
  ///
  /// Without a count or without a run in `origin`, receiving ends `quietPeriod` after the last
  /// file; with a run, it ends when that process ends.
  public init(origin: CollectionOrigin, expectedCount: Int?, quietPeriod: Duration = .seconds(3)) {
    self.origin = origin
    folders = nil
    isFromGit = false
    self.expectedCount = expectedCount
    self.quietPeriod = quietPeriod
    isReceiving = true
    if let run = origin.run {
      watch(run)
    }
  }

  /// Creates a collection of `files` that are all there.
  init(files: [CollectedFile]) {
    origin = nil
    folders = nil
    isFromGit = false
    expectedCount = files.count
    quietPeriod = .zero
    isReceiving = false
    self.files = files.sorted { $0.precedes($1) }
  }

  /// Creates a collection for the files of `folders`, which it compares and follows once it
  /// starts; the targets of links go as text into `linkFolder`, which the caller removes once
  /// the collection is dismissed.
  ///
  /// With `workingTree`, the folders are those of `git difftool --dir-diff` in that working
  /// tree: a link of Git to one of its files stands for that file, and the sides are named as
  /// Git names them rather than after the temporary folders.
  public convenience init(comparing folders: FolderPair, linkFolder: URL, workingTree: URL? = nil) {
    self.init(
      comparer: FolderComparer(folders: folders, linkFolder: linkFolder, workingTree: workingTree))
  }

  /// Creates a collection for two folders that compares them with `comparer` once it starts,
  /// and gathers the changes on disk of every `latency` before it compares them anew.
  init(comparer: FolderComparer, latency: Duration = .milliseconds(300)) {
    origin = nil
    folders = comparer.folders
    isFromGit = comparer.workingTree != nil
    expectedCount = nil
    quietPeriod = .zero
    isReceiving = true
    folderRun = FolderComparisonRun(
      comparer: comparer, latency: latency, files: { [weak self] in self?.files ?? [] },
      onEvent: { [weak self] event in self?.take(event) })
  }

  /// Starts comparing the folders away from the main thread, and following them afterwards;
  /// what the comparison finds comes in as it goes.
  public func startComparing() {
    folderRun?.start()
  }

  /// Waits until every file of the folders is compared once.
  func waitUntilCompared() async {
    await folderRun?.waitUntilCompared()
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

  /// Notes that the window of the collection closed, and stops comparing and watching folders.
  public func dismiss() {
    isDismissed = true
    onChange = nil
    folderRun?.stop()
    folderRun = nil
  }

  /// Takes in what the comparison of the folders found.
  func take(_ event: FolderComparisonRun.Event) {
    guard !isDismissed else { return }
    switch event {
    case .listed(let known, let waiting):
      files = known
      comparedCount = known.count
      pairedCount = known.count + waiting
      onChange?(.updated)
    case .compared(let compared):
      files = Self.merging(compared, into: files)
      comparedCount += compared.count
      onChange?(.updated)
    case .finished:
      comparedCount = files.count
      pairedCount = files.count
      endReceiving()
    case .replaced(let replacement):
      files = replacement
      comparedCount = files.count
      pairedCount = files.count
      onChange?(.updated)
    }
  }

  /// `files` and `others`, each in the order of the list, merged into one list in that order.
  nonisolated static func merging(
    _ others: [CollectedFile], into files: [CollectedFile]
  ) -> [CollectedFile] {
    var merged: [CollectedFile] = []
    merged.reserveCapacity(files.count + others.count)
    var (index, otherIndex) = (files.startIndex, others.startIndex)
    while index < files.endIndex, otherIndex < others.endIndex {
      if others[otherIndex].precedes(files[index]) {
        merged.append(others[otherIndex])
        otherIndex += 1
      } else {
        merged.append(files[index])
        index += 1
      }
    }
    merged += files[index...]
    merged += others[otherIndex...]
    return merged
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
