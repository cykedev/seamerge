import AppKit
import Darwin
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// Opening and closing windows again and again: each window, used as the user uses it, gives
/// back what it took once it closes, with its controller, its text views and the comparisons
/// that undo would bring back.
///
/// Each kind of window opens six times; the first two rounds make what every later one reuses,
/// such as the fonts, the finder and the caches of TextKit. After each round the window and its
/// parts must be gone, and each of the four rounds after the first two may leave at most three
/// times the size of a file more memory in use. A window that stayed, with the comparisons on
/// its steps of undo and the layout of its text, kept fifteen times the size of a file. What a
/// closed window still leaves in a test process takes less than twice that size: the field
/// editor of its find bar and some objects of AppKit, which in the app go once its run loop
/// turns, but in a test process that runs none, stay.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(2))) struct WindowMemoryTests {
  /// The lines of the files, which make each of them about 1 MB, large enough that what a window
  /// keeps stands out from the noise of the process.
  private static let lineCount = 20_000

  @Test func comparisonGivesBackItsMemoryOnceClosed() async throws {
    let largeCase = LargeFileCase(
      name: "memory", lineCount: Self.lineCount, kind: .manySmallChanges)
    let texts = largeCase.texts()
    try await expectEveryRoundGivesBackItsMemory(fileSize: texts.a.utf8.count) {
      let session = try await Session.diff(
        old: SourceFile(bytes: Data(texts.a.utf8), label: "old.swift"),
        new: SourceFile(bytes: Data(texts.b.utf8), label: "new.swift"), mode: .windowDefault)
      let undoManager = UndoManager()
      undoManager.groupsByEvent = false
      let controller = try Windows.controller(for: session, undoManager: undoManager)
      try await use(
        controller, searchingFor: largeCase.searchTexts.common, undoManager: undoManager)
      return try close(controller)
    }
  }

  @Test func mergeGivesBackItsMemoryOnceClosed() async throws {
    let largeCase = LargeFileCase(
      name: "memory", lineCount: Self.lineCount * 5, kind: .conflictingLines)
    let texts = largeCase.texts()
    try await expectEveryRoundGivesBackItsMemory(fileSize: texts.a.utf8.count) {
      let session = try await SampleMerges.merge(base: texts.base, a: texts.a, b: texts.b)
      let undoManager = UndoManager()
      undoManager.groupsByEvent = false
      let controller = try Windows.controller(for: session, undoManager: undoManager)
      try await use(
        controller, searchingFor: largeCase.searchTexts.common, undoManager: undoManager)
      return try close(controller)
    }
  }

  @Test func windowOfSeveralFilesGivesBackItsMemoryOnceClosed() async throws {
    let largeCase = LargeFileCase(
      name: "memory", lineCount: Self.lineCount, kind: .manySmallChanges)
    let texts = largeCase.texts()
    let folder = try SampleCollections.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = [
      try SampleCollections.file(
        "Sources/Large.swift", old: texts.a, new: texts.b, number: 1, count: 2, in: folder),
      try SampleCollections.file(
        "Sources/Order.swift", old: SampleCollections.orderOld, new: SampleCollections.orderNew,
        number: 2, count: 2, in: folder),
    ]
    try await expectEveryRoundGivesBackItsMemory(
      fileSize: texts.a.utf8.count, knownIssue: Self.textViewsOfSeveralFiles
    ) {
      let controller = try await Windows.controller(for: FileCollection(files: files))
      try await use(controller, searchingFor: largeCase.searchTexts.common)
      controller.showFile(at: 1)
      await controller.fileLoad?.value
      return try close(controller)
    }
  }

  @Test func comparisonOfFoldersGivesBackItsMemoryOnceClosed() async throws {
    let largeCase = LargeFileCase(
      name: "memory", lineCount: Self.lineCount, kind: .manySmallChanges)
    let texts = largeCase.texts()
    let folders = try SampleFolders()
    try folders.write("Large.swift", left: texts.a, right: texts.b)
    try folders.write(
      "Order.swift", left: SampleCollections.orderOld, right: SampleCollections.orderNew)
    try folders.write("Same.swift", left: SampleFolders.order, right: SampleFolders.order)
    let pair = folders.pair
    let linkFolder = folders.folder.appending(path: "links")
    try await expectEveryRoundGivesBackItsMemory(
      fileSize: texts.a.utf8.count, knownIssue: Self.textViewsOfSeveralFiles
    ) {
      let collection = FileCollection(
        comparer: FolderComparer(folders: pair, linkFolder: linkFolder))
      collection.startComparing()
      await collection.waitUntilCompared()
      let controller = try await Windows.controller(for: collection)
      await controller.fileLoad?.value
      #expect(controller.shownFile?.path == "Large.swift")
      try await use(controller, searchingFor: largeCase.searchTexts.common)
      controller.showFile(at: 1)
      await controller.fileLoad?.value
      return try close(controller)
    }
  }

  /// Why a window of several files may fail.
  ///
  /// After a switch of the comparison, a search and scrolling, its two text views stay in the
  /// test process, and with them some memory each round. Who keeps them is open; without one of
  /// the three, they go.
  private static let textViewsOfSeveralFiles: Comment =
    "The text views of a window of several files stay after switching, searching and scrolling"

  // MARK: - Rounds

  /// What a window was made of, held weakly, to tell whether it is gone.
  private struct Parts {
    weak var controller: SessionWindowController?
    weak var window: NSWindow?
    weak var collection: FileCollection?
    var textViews: [WeakTextView]

    struct WeakTextView {
      weak var view: NSTextView?
    }

    var remaining: [String] {
      var names: [String] = []
      if controller != nil { names.append("controller") }
      if window != nil { names.append("window") }
      if collection != nil { names.append("collection") }
      let views = textViews.filter { $0.view != nil }.count
      if views > 0 { names.append("\(views) text views") }
      return names
    }
  }

  /// Carries out `round`, which opens a window, uses it and closes it, six times, each time
  /// expecting the window gone afterwards, and each of the last four to leave less than three
  /// times `fileSize` bytes more in use; with `knownIssue`, a failure is known and named so.
  private func expectEveryRoundGivesBackItsMemory(
    fileSize: Int, knownIssue: Comment? = nil, _ round: () async throws -> Parts
  ) async throws {
    try await FindPasteboard.preserving {
      var inUse: [Int] = []
      for index in 0..<6 {
        let parts = try await round()
        await settle(until: parts)
        inUse.append(Self.bytesInUse())
        let check = {
          #expect(parts.remaining.isEmpty, "Round \(index + 1) left \(parts.remaining)")
        }
        if let knownIssue {
          withKnownIssue(knownIssue, isIntermittent: true, check)
        } else {
          check()
        }
      }
      let growth = inUse[5] - inUse[1]
      let rounds = inUse.map { String(format: "%.1f", Double($0) / 1_048_576) }
      let check = {
        #expect(
          growth < 4 * 3 * fileSize,
          "\(growth) bytes more in use after four rounds with files of \(fileSize) bytes: \(rounds)"
        )
      }
      if let knownIssue {
        withKnownIssue(knownIssue, isIntermittent: true, check)
      } else {
        check()
      }
    }
  }

  /// Lets the main actor go until the parts of the closed window are gone, or for at most two
  /// seconds: the work the window left, such as a search on a thread of its own or a timer that
  /// waits for scrolling to rest, ends, and what it left to the autorelease pools goes with the
  /// task that left it.
  private func settle(until parts: Parts) async {
    let deadline = ContinuousClock.now + .seconds(2)
    repeat {
      try? await Task.sleep(for: .milliseconds(50))
    } while !parts.remaining.isEmpty && ContinuousClock.now < deadline
  }

  /// Uses the window of `controller` as the user does: switches the comparison mode there and
  /// back, as two steps of undo of `undoManager` if given, searches for `needle` and scrolls
  /// each pane to its end and back to its middle.
  private func use(
    _ controller: SessionWindowController, searchingFor needle: String,
    undoManager: UndoManager? = nil
  ) async throws {
    let window = try #require(controller.window)
    for mode in [ComparisonMode.exact, .windowDefault] {
      undoManager?.beginUndoGrouping()
      await controller.switchComparison(to: ComparisonOptions(mode: mode))
      undoManager?.endUndoGrouping()
      autoreleasepool { window.contentView?.layoutSubtreeIfNeeded() }
    }
    #expect(controller.comparisonOptions.mode == .windowDefault)

    let driver = SearchDriver(controller)
    #expect(try driver.send(.find))
    try driver.type(needle)
    await driver.waitForMatches { [search = driver.search] in !search.matches.isEmpty }

    for pane in Windows.panes(of: controller) {
      let textView = pane.documentView
      let scrollView = try #require(textView.enclosingScrollView)
      let clip = scrollView.contentView
      let end = max(0, textView.frame.height - clip.bounds.height)
      for y in [end, end / 2] {
        autoreleasepool {
          clip.scroll(to: NSPoint(x: 0, y: y))
          scrollView.reflectScrolledClipView(clip)
          window.contentView?.layoutSubtreeIfNeeded()
        }
      }
      // The test process runs no run loop of its own, which in the app fires the timer that
      // waits for scrolling to rest and the passes of discarding once it is idle.
      pane.textView.scrollRestTimer?.fire()
      while pane.textView.discardNextParagraphs() {}
    }
  }

  /// Closes the window of `controller` and returns its parts.
  private func close(_ controller: SessionWindowController) throws -> Parts {
    let window = try #require(controller.window)
    let parts = Parts(
      controller: controller, window: window, collection: controller.collection,
      textViews: Windows.panes(of: controller).map { Parts.WeakTextView(view: $0.documentView) })
    autoreleasepool { window.close() }
    return parts
  }

  /// The bytes that the process has allocated and not freed.
  ///
  /// Unlike its footprint, it leaves out the pages that freed memory leaves between allocations,
  /// which grow and shrink with the order of the allocations rather than with what is kept.
  private static func bytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
  }
}
