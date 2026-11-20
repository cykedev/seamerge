import Foundation
import Testing

@testable import SeamergeUI

/// The watch of the files of a window: when it has them reloaded, and when it holds back.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiskWatchTests {
  /// A window that answers as told and counts its reloads; with `holdsReloads`, each reload
  /// waits until the test lets it end.
  @MainActor
  private final class Window: DiskWatchDelegate {
    var readiness = DiskWatch.Readiness.ready
    var holdsReloads = false
    private(set) var reloadCount = 0
    private var heldReload: CheckedContinuation<Void, Never>?
    private let reloads: AsyncStream<Int>.Continuation
    let reloadCounts: AsyncStream<Int>

    init() {
      (reloadCounts, reloads) = AsyncStream.makeStream()
    }

    func readinessToReload(for watch: DiskWatch) -> DiskWatch.Readiness {
      readiness
    }

    func reloadChangedFiles(for watch: DiskWatch) async {
      reloadCount += 1
      reloads.yield(reloadCount)
      if holdsReloads {
        await withCheckedContinuation { heldReload = $0 }
      }
    }

    func endHeldReload() {
      heldReload?.resume()
      heldReload = nil
    }
  }

  @Test func changeWhileTheWindowIsBusyIsLookedAtOnceItIsFree() async {
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window
    window.readiness = .busy

    await watch.reloadChangedFiles()
    #expect(window.reloadCount == 0)

    window.readiness = .ready
    watch.lookAgainIfAsked()
    var counts = window.reloadCounts.makeAsyncIterator()
    #expect(await counts.next() == 1)
  }

  @Test func changeDuringAReloadIsLookedAtAfterIt() async {
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window
    window.holdsReloads = true
    var counts = window.reloadCounts.makeAsyncIterator()

    let first = Task { await watch.reloadChangedFiles() }
    #expect(await counts.next() == 1)
    #expect(watch.isReloading)
    await watch.reloadChangedFiles()
    #expect(window.reloadCount == 1)

    window.holdsReloads = false
    window.endHeldReload()
    await first.value
    #expect(await counts.next() == 2)
  }

  @Test func windowWithNothingToReloadIsNotAskedToReload() async {
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window
    window.readiness = .nothingToReload

    await watch.reloadChangedFiles()
    window.readiness = .ready
    watch.lookAgainIfAsked()
    // A look that the window asked for would run before this one, which comes after it.
    await Task { await watch.reloadChangedFiles() }.value

    #expect(window.reloadCount == 1)
  }

  @Test func eachFileIsWatchedOnceInTheOrderGiven() {
    let folder = FileManager.default.temporaryDirectory
    let name = "DiskWatchTests-\(UUID().uuidString)"
    let (a, b) = (folder.appending(path: "\(name)-a.txt"), folder.appending(path: "\(name)-b.txt"))
    let watch = DiskWatch()

    watch.watch([b, a, b])
    #expect(watch.watchedURLs == [b, a])
    watch.stop()
    #expect(watch.watchedURLs.isEmpty)
  }

  @Test func burstOfChangesIsOneLookAtTheFiles() async {
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window

    for _ in 0..<3 {
      watch.filesMayHaveChanged()
    }
    // The look runs before this task, which comes after it.
    await Task {}.value
    #expect(window.reloadCount == 1)

    watch.filesMayHaveChanged()
    await Task {}.value
    #expect(window.reloadCount == 2)
  }

  @Test func changeOfAWatchedFileHasTheWindowReload() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "DiskWatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "watched.txt")
    try Data("one\n".utf8).write(to: url)
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window
    watch.watch([url])
    var counts = window.reloadCounts.makeAsyncIterator()

    try Data("two\n".utf8).write(to: url, options: .atomic)

    #expect(await counts.next() == 1)
  }

  @Test func fileModifiedSinceItWasReadIsLookedAtOnceAndOnlyThen() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "DiskWatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let url = folder.appending(path: "read.txt")
    let readSince = Date()
    try Data("one\n".utf8).write(to: url)
    let window = Window()
    let watch = DiskWatch()
    watch.delegate = window
    watch.watch([url, URL(filePath: "/dev/null")])

    watch.lookIfModified(since: Date.distantFuture)
    await Task {}.value
    #expect(window.reloadCount == 0)

    watch.lookIfModified(since: readSince)
    await Task {}.value
    #expect(window.reloadCount == 1)
  }

  @Test func dateWithAFractionCountsAsItIsAndOneInWholeSecondsWithLeeway() {
    let read = Date(timeIntervalSinceReferenceDate: 800_000_000.5)

    #expect(DiskWatch.mayHaveBeenModified(at: read, since: read))
    #expect(!DiskWatch.mayHaveBeenModified(at: read - 0.001, since: read))
    #expect(DiskWatch.mayHaveBeenModified(at: read - 1.5, since: read))
    #expect(!DiskWatch.mayHaveBeenModified(at: read - 2.5, since: read))
  }
}
