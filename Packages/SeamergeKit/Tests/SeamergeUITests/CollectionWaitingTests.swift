import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A window that compares several files and shows before a file is compared: it opens with the
/// headers of its first file and empty panes, waits with them for a file the user goes to, and
/// shows only the file in view, never one it no longer waits for.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct CollectionWaitingTests {
  /// A window of `collection` that waits for the comparison of its first file, which the test
  /// finishes when it likes.
  @MainActor
  private struct Waiting {
    let controller: SessionWindowController
    let finish: () -> Void
  }

  private func waiting(
    for collection: FileCollection, settings: UserSettings = .private()
  ) async throws -> Waiting {
    let (go, continuation) = AsyncStream.makeStream(of: Void.self)
    let opening = try await SessionWindowController.opening(collection, settings: settings)
    let comparison = try #require(opening.comparison)
    let held = PendingFile {
      var iterator = go.makeAsyncIterator()
      await iterator.next()
      return await comparison.value
    }
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let controller = SessionWindowController(
      session: opening.session, context: opening.context, undoManager: UndoManager(),
      displayOptions: DisplayOptions(reducesMotion: true), pasteboard: .withUniqueName(),
      workspace: WorkspaceRecorder(), prompts: PromptRecorder(), doneStyle: .standard,
      settings: settings, window: SessionWindow(), collection: collection, pendingFile: held)
    return Waiting(controller: controller) {
      continuation.yield()
      continuation.finish()
    }
  }

  private static func commit() throws -> FileCollection {
    FileCollection(files: try SampleCollections.commit(in: try SampleCollections.folder()))
  }

  @Test func slowFirstFileShowsTheWindowWithItsHeadersBeforeItsLines() async throws {
    let collection = try Self.commit()
    let waiting = try await waiting(for: collection)
    let controller = waiting.controller
    defer { controller.window?.close() }
    let first = collection.files[0]

    #expect(controller.waitsForComparison)
    #expect(controller.toolbarCount == .waiting)
    #expect(controller.window?.title == first.path)
    let opened = try await Windows.controller(for: try Self.commit())
    defer { opened.window?.close() }
    #expect(
      controller.presentation.headers.mapValues(\.name)
        == opened.presentation.headers.mapValues(\.name))
    for pane in Windows.panes(of: controller) {
      #expect(pane.documentView.string.isEmpty)
      #expect(pane.documentView.accessibilityPlaceholderValue() == "Comparing…")
    }
    #expect(!controller.canPerform(.nextChange))
    #expect(controller.canPerform(.nextFile))
    #expect(controller.collectionLayout?.fileList.tableView.selectedRow == 0)

    waiting.finish()
    await controller.phase.filling?.value
    #expect(!controller.waitsForComparison)
    #expect(controller.presentation.changes.blocks == opened.presentation.changes.blocks)
    #expect(controller.presentation.currentBlock == opened.presentation.currentBlock)
    for (filled, shown) in zip(Windows.panes(of: controller), Windows.panes(of: opened)) {
      #expect(filled.documentView.string == shown.documentView.string)
      #expect(filled.documentView.accessibilityPlaceholderValue() == nil)
    }
    #expect(controller.canPerform(.nextChange))
  }

  @Test func fileShownWhileTheFirstIsComparedStaysWhenTheFirstIsReady() async throws {
    let collection = try Self.commit()
    let waiting = try await waiting(for: collection)
    let controller = waiting.controller
    defer { controller.window?.close() }

    controller.showFile(at: 2)
    await controller.fileLoad?.value
    waiting.finish()
    // Gives the comparison of the first file the time to arrive, which then shows nowhere.
    for _ in 0..<20 {
      await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(50))

    let file = collection.files[2]
    #expect(controller.collectionNavigator?.shownFile == file)
    #expect(controller.window?.title == file.path)
    #expect(controller.presentation.changes.session.inputs.b.label == file.new.label)
    #expect(!controller.waitsForComparison)
    #expect(!controller.presentation.changes.blocks.isEmpty)
  }

  @Test func windowClosedWhileItComparesShowsAndKeepsNothing() async throws {
    let collection = try Self.commit()
    let waiting = try await waiting(for: collection)
    let controller = waiting.controller
    let load = try #require(controller.fileLoad)

    controller.window?.close()
    #expect(load.isCancelled)
    waiting.finish()
    await load.value

    #expect(controller.presentation.changes.blocks.isEmpty)
    #expect(controller.collectionNavigator?.readFiles.isEmpty == true)
    for pane in Windows.panes(of: controller) {
      #expect(pane.documentView.string.isEmpty)
    }
  }

  @Test func fileNotReadyAtOnceShowsItsHeadersAndTellsVoiceOverOnceItIsCompared() async throws {
    let collection = try Self.commit()
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    controller.window?.orderFront(nil)
    controller.fileWait = 0
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }

    controller.showFile(at: 2)
    // The window shows the headers of the file before its lines are there.
    while !controller.waitsForComparison {
      await Task.yield()
    }
    #expect(controller.window?.title == collection.files[2].path)
    #expect(controller.presentation.headers[.b]?.name == "README.md")
    for pane in Windows.panes(of: controller) {
      #expect(pane.documentView.string.isEmpty)
    }
    await controller.fileLoad?.value

    #expect(!controller.waitsForComparison)
    #expect(controller.layout.sourcePane(.b)?.documentView.string.isEmpty == false)
    #expect(announcements == ["Files compared. 1 Change"])
  }

  @Test func fileGoneToWhileAnotherWaitsTakesItsPlace() async throws {
    let collection = try Self.commit()
    let controller = try await Windows.controller(for: collection)
    defer { controller.window?.close() }
    controller.fileWait = 0

    controller.showFile(at: 2)
    while !controller.waitsForComparison {
      await Task.yield()
    }
    let waited = try #require(controller.phase.filling)
    controller.showFile(at: 3)
    await controller.fileLoad?.value
    await waited.value

    let file = collection.files[3]
    #expect(controller.collectionNavigator?.shownFile == file)
    #expect(controller.window?.title == file.path)
    #expect(controller.presentation.changes.session.inputs.b.label == file.new.label)
    #expect(!controller.waitsForComparison)
    #expect(!controller.showsComparisonProgress)
  }

  @Test func fileWaitedForThatWentFromTheFoldersEndsTheWait() async throws {
    let folders = try SampleFolders()
    try folders.write("README.md", left: "old\n", right: "new\n")
    let comparer = FolderComparer(
      folders: folders.pair, linkFolder: folders.folder.appending(path: "links"))
    let collection = FileCollection(comparer: comparer)
    collection.take(
      .listed(
        comparer.pairs(at: "").map { comparer.file(for: $0, change: comparer.change(of: $0)) },
        waiting: 0))
    collection.take(.finished)
    let waiting = try await waiting(for: collection)
    let controller = waiting.controller
    defer { controller.window?.close() }
    #expect(controller.waitsForComparison)

    collection.take(.replaced([]))

    #expect(controller.phase.placeholder == .sameFiles)
    #expect(!controller.waitsForComparison)
    #expect(controller.toolbarCount == .nothing)
    #expect(!controller.showsComparisonProgress)
    for pane in Windows.panes(of: controller) {
      #expect(pane.documentView.accessibilityPlaceholderValue() == nil)
    }
    waiting.finish()
    await controller.fileLoad?.value
    #expect(controller.phase.placeholder == .sameFiles)
    #expect(!controller.waitsForComparison)
  }

  /// Making the sides of the file in view equal on disk changes only what the list says about
  /// it, not its sides; the window goes on to show the file it reads and reads the next ahead.
  @Test func fileInViewWhoseChangeAloneChangesWhileItIsReadShowsAndReadsAhead() async throws {
    let folders = try SampleFolders()
    try folders.write("notes.txt", left: "old\n", right: "new\n")
    try folders.write("README.md", left: "old\n", right: "new\n")
    let comparer = FolderComparer(
      folders: folders.pair, linkFolder: folders.folder.appending(path: "links"))
    let collection = FileCollection(comparer: comparer)
    collection.take(
      .listed(
        comparer.pairs(at: "").map { comparer.file(for: $0, change: comparer.change(of: $0)) },
        waiting: 0))
    collection.take(.finished)
    let waiting = try await waiting(for: collection)
    let controller = waiting.controller
    defer { controller.window?.close() }
    let navigator = try #require(controller.collectionNavigator)
    let shown = try #require(navigator.shownFile)
    let next = collection.files[1]

    let identical = CollectedFile(
      old: shown.old, new: shown.new, difftool: shown.difftool, change: .identical)
    collection.take(.replaced([identical, next]))
    waiting.finish()
    await controller.phase.filling?.value
    await controller.fileLoad?.value

    #expect(navigator.shownFile == identical)
    #expect(!controller.waitsForComparison)
    #expect(controller.layout.sourcePane(.b)?.documentView.string.isEmpty == false)
    #expect(navigator.readFiles.keys.contains(next), "Read ahead")
  }

  @Test func rulesChangedWhileTheFirstFileIsComparedApplyOnceItShows() async throws {
    let settings = UserSettings.private()
    let collection = try Self.commit()
    let waiting = try await waiting(for: collection, settings: settings)
    let controller = waiting.controller
    defer { controller.window?.close() }

    settings.enabledBuiltInIgnoreRules = [.timestamps]
    for _ in 0..<20 {
      await Task.yield()
    }
    // The empty panes are not compared anew.
    #expect(controller.waitsForComparison)
    #expect(!controller.comparisonSwitcher.isComparing)
    #expect(controller.presentation.changes.session.ignoreRules.isEmpty)

    waiting.finish()
    await controller.phase.filling?.value
    let rules = settings.ignoreRules.filter(\.isEnabled)
    for _ in 0..<200
    where controller.comparisonSwitcher.isComparing
      || controller.presentation.changes.session.ignoreRules != rules
    {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.presentation.changes.session.ignoreRules == rules)
    #expect(controller.collectionNavigator?.shownFile == collection.files[0])
  }

  @Test func panesOfAComparisonAreMadeAlikeWhateverItsFilesAreCalled() async throws {
    let controller = try Windows.controller(for: try await SampleDiffs.greeting())
    defer { controller.window?.close() }
    let other = try await SampleDiffs.diff(old: "a\n", new: "b\n", label: "Notes.txt")
    let renamed = SideHeader.headers(of: other, context: SessionContext())
    let setup = controller.presentation.setup
    #expect(renamed.mapValues(\.name) != controller.presentation.headers.mapValues(\.name))

    controller.presentation.show(renamed)

    #expect(controller.presentation.setup == setup)
    // The decision column of a merge names the inputs.
    let merge = try Windows.controller(for: try await SampleMerges.example())
    defer { merge.window?.close() }
    #expect(merge.presentation.setup.headers == merge.presentation.headers)
  }
}
