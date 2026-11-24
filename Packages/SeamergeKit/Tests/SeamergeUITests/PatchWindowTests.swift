import AppKit
import FolderCompare
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The window of a patch: its sides with the numbers of the hunks and the bars of the lines the
/// patch passes over, that nothing in it can be changed, the window of several files, and that
/// its copy goes with it.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct PatchWindowTests {
  /// A cache of patches in a folder of its own, removed with the fixture.
  @MainActor
  private final class Fixture {
    let files: SampleFiles
    let cache: PatchCache

    init() throws {
      files = try SampleFiles()
      cache = PatchCache(folder: files.folder.appending(path: "Patch", directoryHint: .isDirectory))
    }

    /// The copies the cache holds, each a folder.
    var copies: [String] {
      get throws {
        let path = cache.folder.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: path)
      }
    }

    /// The window of `patch`, read from a file named `fileName`, as the app opens it.
    func window(
      _ patch: Data, fileName: String? = "change.patch"
    ) async throws -> SessionWindowController {
      let copy = try await cache.keep(patch, fileName: fileName)
      let controller = try await SessionWindowController.openPatch(
        copy, undoManager: UndoManager(), settings: .private())
      await controller.phase.filling?.value
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      return controller
    }
  }

  /// A file of 100 numbered lines in which line 10 and line 50 changed, as a patch of Git.
  static let changedFile: Data = {
    let old = (1...100).map { "line \($0)\n" }.joined()
    let new = old.replacingOccurrences(of: "line 10\n", with: "ten\n")
      .replacingOccurrences(of: "line 50\n", with: "fifty\nfifty-one\n")
    return patch([("Sources/numbers.txt", old, new)])
  }()

  /// The patch of `files`, each a path with its older and its newer text, `nil` where it is
  /// missing.
  static func patch(_ files: [(path: String, old: String?, new: String?)]) -> Data {
    let side: (String?) -> UnifiedDiff.File.Side = { text in
      text.map { .file(SourceFile(bytes: Data($0.utf8), label: "side")) } ?? .missing
    }
    let files = files.map {
      UnifiedDiff.File(old: side($0.old), new: side($0.new), names: .path($0.path))
    }
    do {
      return try UnifiedDiff.data(of: files)
    } catch {
      preconditionFailure("The patch of the samples cannot be written: \(error)")
    }
  }

  @Test func sidesShowTheNumbersOfTheHunksWithBarsForTheLinesBetween() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    defer { controller.window?.close() }

    let old = try #require(controller.layout.sourcePane(.a))
    let new = try #require(controller.layout.sourcePane(.b))
    let oldNumbers: [Int32] = [5] + Array(6...12) + [45] + Array(46...52)
    let newNumbers: [Int32] = [5] + Array(6...12) + [45] + Array(46...53)
    #expect(old.content.lineNumbers.filter { $0 >= 0 } == oldNumbers)
    #expect(new.content.lineNumbers.filter { $0 >= 0 } == newNumbers)
    for pane in [old, new] {
      #expect(pane.collapsedRuns.map(\.missingLineCount) == [6, 33])
      #expect(pane.collapsedRuns.map(\.rows.count) == [1, 1])
    }
    #expect(controller.window?.title == "change.patch")
    #expect(controller.presentation.headers[.a]?.name == "Sources/numbers.txt")
  }

  @Test func barsOfLinesNotInThePatchStayWhenEveryLineShows() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    defer { controller.window?.close() }
    let pane = try #require(controller.layout.sourcePane(.b))

    controller.showAllLines(nil)
    #expect(pane.collapsedRuns.map(\.missingLineCount) == [6, 33])

    let gap = try #require(pane.collapsedRuns.first)
    controller.presentation.pane(pane, didAskToExpand: gap)
    #expect(pane.collapsedRuns.count == 2)
  }

  @Test func singleColumnAndConnectedSidesNumberAndBarTheLinesAsWell() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    defer { controller.window?.close() }

    controller.showSingleColumn(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let column = try #require(controller.layout.columnPane)
    #expect(column.collapsedRuns.map(\.missingLineCount) == [6, 33])
    let sides = try #require(column.content.sideLineNumbers)
    #expect(sides.right.filter { $0 >= 0 } == [5] + Array(6...12) + [45] + Array(46...53))

    controller.showConnectedSides(nil)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let old = try #require(controller.layout.sourcePane(.a))
    #expect(old.content.lineNumbers == [5] + Array(6...12) + [45] + Array(46...52))
    #expect(old.collapsedRuns.map(\.missingLineCount) == [6, 33])
  }

  @Test func goToLineFindsALineByItsNumberInTheFile() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    defer { controller.window?.close() }
    let pane = try #require(controller.layout.sourcePane(.b))

    let row = controller.presentation.go(toLine: 47, in: pane)

    #expect(pane.content.lineNumbers[row] == 47)
  }

  @Test func nothingInTheWindowOfAPatchCanBeChanged() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    defer { controller.window?.close() }
    controller.presentation.jump(to: 0)

    for command in [
      SessionCommand.copyToRight, .copyToLeft, .copyAllChangesToRight, .copyAllChangesToLeft,
      .openInEditor,
      .exportPatch, .copyPatch, .changeFiles, .save,
    ] {
      #expect(!controller.canPerform(command), "\(command)")
    }
    #expect(controller.headerMenu(for: .a) == nil)
    #expect(controller.headerMenu(for: .b) == nil)
    let location = try #require(controller.presentation.headers[.b]?.details.location)
    #expect(location == "Sources/numbers.txt")
  }

  @Test func patchFromStandardInputIsTitledPatch() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile, fileName: nil)
    defer { controller.window?.close() }

    #expect(controller.window?.title == "Patch")
  }

  @Test func severalFilesShowInAListInTheOrderOfThePatch() async throws {
    let fixture = try Fixture()
    let patch = Self.patch([
      ("b/changed.txt", "one\ntwo\n", "one\n2\n"), ("a/added.txt", nil, "new\n"),
      ("c/deleted.txt", "old\n", nil),
    ])
    let controller = try await fixture.window(patch)
    defer { controller.window?.close() }

    let collection = try #require(controller.collectionNavigator?.collection)
    #expect(collection.files.map(\.path) == ["b/changed.txt", "a/added.txt", "c/deleted.txt"])
    #expect(collection.files.map(\.change) == [.modified, .added, .deleted])
    #expect(!collection.isReceiving)
    #expect(controller.window?.title == "change.patch")
    controller.showNextFile(nil)
    await controller.fileLoad?.value
    #expect(controller.context.patch != nil)
    #expect(!controller.canPerform(.copyAllChangesToLeft))
    let names = [Role.a, .b].map { controller.presentation.headers[$0]?.name }
    #expect(names == ["New File", "a/added.txt"])
  }

  @Test func binaryFileSaysThatThePatchHoldsNoLinesOfIt() async throws {
    let fixture = try Fixture()
    let patch = Data(
      """
      diff --git a/logo.png b/logo.png
      index 1111111..2222222 100644
      Binary files a/logo.png and b/logo.png differ

      """.utf8)
    let controller = try await fixture.window(patch)
    defer { controller.window?.close() }

    let unavailable = try #require(controller.phase.unavailable)
    guard case .binaryFileInPatch(let url) = unavailable.reason else {
      Issue.record("The window gives another reason: \(unavailable.reason)")
      return
    }
    #expect(url.lastPathComponent == "logo.png")
    #expect(
      controller.phase.unavailable?.message(in: controller.context)
        == "The patch only says that the file differs, as for a binary file.")
  }

  @Test func copyLiesInTheCacheAndGoesWithTheWindow() async throws {
    let fixture = try Fixture()
    let controller = try await fixture.window(Self.changedFile)
    let copy = try #require(controller.context.patch)
    #expect(try fixture.copies == [copy.folder.lastPathComponent])
    #expect(copy.folder.deletingLastPathComponent().lastPathComponent == "Patch")

    controller.close()

    #expect(try fixture.copies.isEmpty)
  }

  @Test func leftoversOfAnEarlierRunGoAndCopiesMadeSinceStay() async throws {
    let fixture = try Fixture()
    let leftover = try await fixture.cache.keep(Self.changedFile, fileName: nil)
    let start = Date.now.addingTimeInterval(1)
    try FileManager.default.setAttributes(
      [.creationDate: start.addingTimeInterval(-60)],
      ofItemAtPath: leftover.folder.path(percentEncoded: false))
    let fresh = try await fixture.cache.keep(Self.changedFile, fileName: nil)
    try FileManager.default.setAttributes(
      [.creationDate: start.addingTimeInterval(60)],
      ofItemAtPath: fresh.folder.path(percentEncoded: false))

    await fixture.cache.removeLeftovers(madeBefore: start)

    #expect(try fixture.copies == [fresh.folder.lastPathComponent])
  }

  @Test func patchThatCannotBeReadKeepsNothing() async throws {
    let fixture = try Fixture()

    await #expect(throws: SessionLoadingError.unreadablePatch) {
      try await fixture.cache.keep(Data("--- a\n+++ b\n@@ -1,3 +1 @@\n".utf8), fileName: nil)
    }
    #expect(try fixture.copies.isEmpty)
  }

  /// A patch of 50 000 lines is read, kept and compared away from the main actor, which goes on
  /// turning while the window opens; the longest pause is printed with the test.
  @Test func largePatchOpensWithoutBlockingTheMainActor() async throws {
    let fixture = try Fixture()
    let old = (1...40_000).map { "line \($0) of a large file\n" }.joined()
    let new = (1...40_000).map { $0 % 2 == 0 ? "changed \($0)\n" : "line \($0) of a large file\n" }
      .joined()
    let patch = Self.patch([("large.txt", old, new)])
    let lineCount = patch.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    #expect(lineCount >= 50_000)
    let clock = ContinuousClock()
    var longestPause = Duration.zero
    let opened = OpenedWindow()
    let opening = Task {
      defer { opened.isSet = true }
      opened.controller = try await fixture.window(patch)
    }
    var last = clock.now
    while !opened.isSet {
      await Task.yield()
      let now = clock.now
      longestPause = max(longestPause, now - last)
      last = now
    }
    try await opening.value
    let controller = try #require(opened.controller)
    defer { controller.window?.close() }

    print(
      "Longest pause of the main actor while \(lineCount) lines of a patch open: \(longestPause)")
    #expect(controller.presentation.changes.blocks.count > 3000)
    #expect(longestPause < .seconds(1))
  }
}

/// The window that a task opens, and whether the task has ended.
@MainActor
private final class OpenedWindow {
  var controller: SessionWindowController?
  var isSet = false
}
