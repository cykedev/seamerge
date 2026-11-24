import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A window that opens before the comparison of its files is ready: it shows their headers and
/// empty panes, acts on nothing, and fills once the comparison is there, or says why it failed.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct PendingComparisonTests {
  /// A comparison that the test finishes when it likes, and a window that waits for it.
  @MainActor
  private struct Waiting {
    let controller: SessionWindowController
    let finish: (Result<Session, SessionLoadingError>) -> Void

    /// Finishes the comparison with `outcome` and waits until the window has shown it.
    func fill(with outcome: Result<Session, SessionLoadingError>) async {
      finish(outcome)
      await controller.phase.filling?.value
    }
  }

  private static let files = Session.Inputs(
    a: SessionFile(url: URL(filePath: "/tmp/old/Greeting.swift"), label: "Greeting.swift"),
    b: SessionFile(url: URL(filePath: "/tmp/new/Greeting.swift"), label: "Greeting.swift"))

  private static let mergeFiles = Session.Inputs(
    base: SessionFile(url: URL(filePath: "/tmp/base/Settings.swift"), label: "Settings.swift"),
    a: SessionFile(url: URL(filePath: "/tmp/theirs/Settings.swift"), label: "Settings.swift"),
    b: SessionFile(url: URL(filePath: "/tmp/ours/Settings.swift"), label: "Settings.swift"))

  private func waiting(
    for files: Session.Inputs<SessionFile> = files, kind: Session.Kind = .diff,
    options: DisplayOptions = DisplayOptions(reducesMotion: true)
  ) async throws -> Waiting {
    let (outcomes, continuation) = AsyncStream.makeStream(
      of: Result<Session, SessionLoadingError>.self)
    let comparison = PendingComparison {
      var iterator = outcomes.makeAsyncIterator()
      return await iterator.next() ?? .failure(.comparisonFailed)
    }
    let empty = try await SessionWindowController.emptySession(
      of: files, kind: kind, mode: .windowDefault)
    let controller = try Windows.controller(
      for: empty, options: options, pendingComparison: comparison)
    return Waiting(controller: controller) { continuation.yield($0) }
  }

  @Test func windowThatWaitsShowsTheHeadersAndEmptyPanesThatSayItCompares() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }

    #expect(controller.waitsForComparison)
    #expect(controller.window?.title == "Greeting.swift")
    #expect(controller.presentation.headers[.a]?.name == "Greeting.swift")
    for pane in Windows.panes(of: controller) {
      #expect(pane.documentView.string.isEmpty)
      #expect(pane.documentView.accessibilityPlaceholderValue() == "Comparing…")
    }
    #expect(!controller.showsComparisonProgress)
  }

  @Test func windowThatWaitsAMomentSaysSoInTheToolbarUntilItFills() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }

    for _ in 0..<500 where !controller.showsComparisonProgress {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.showsComparisonProgress)

    await waiting.fill(with: .success(try await SampleDiffs.greeting()))
    #expect(!controller.showsComparisonProgress)
  }

  @Test func windowThatWaitsComparesInTheModeItWasAskedFor() async throws {
    let empty = try await SessionWindowController.emptySession(
      of: Self.files, kind: .diff, mode: .exact)
    let controller = try Windows.controller(
      for: empty, pendingComparison: PendingComparison { .failure(.comparisonFailed) })
    defer { controller.window?.close() }
    #expect(controller.comparisonOptions.mode == .exact)
  }

  @Test func windowThatWaitsActsOnNoCommandOfTheLines() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }

    for command in [
      SessionCommand.nextChange, .showAllLines, .compareExactly, .showSingleColumn, .goToLine,
    ] {
      #expect(!controller.canPerform(command), "\(command)")
    }
    #expect(controller.canPerform(.toggleFooter))
  }

  @Test func windowFillsOnceTheComparisonIsReadyAsAWindowOpenedWithIt() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }
    let session = try await SampleDiffs.greeting()
    let opened = try Windows.controller(for: session)
    defer { opened.window?.close() }

    await waiting.fill(with: .success(session))
    #expect(!controller.waitsForComparison)
    #expect(controller.presentation.changes.blocks == opened.presentation.changes.blocks)
    #expect(controller.presentation.currentBlock == opened.presentation.currentBlock)
    for (filled, shown) in zip(Windows.panes(of: controller), Windows.panes(of: opened)) {
      #expect(filled.documentView.string == shown.documentView.string)
      #expect(filled.content.blocks == shown.content.blocks)
      #expect(filled.documentView.accessibilityPlaceholderValue() == nil)
    }
    #expect(controller.window?.subtitle == opened.window?.subtitle)
    #expect(controller.canPerform(.nextChange) == opened.canPerform(.nextChange))
  }

  @Test func mergeFillsWithItsResultAndCountsItsConflicts() async throws {
    let waiting = try await waiting(for: Self.mergeFiles, kind: .merge)
    let controller = waiting.controller
    defer { controller.window?.close() }
    let session = try await SampleMerges.example()
    let opened = try Windows.controller(for: session)
    defer { opened.window?.close() }
    #expect(!controller.isResultEdited)

    await waiting.fill(with: .success(session))
    #expect(
      controller.presentation.navigation.openConflictCount
        == opened.presentation.navigation.openConflictCount)
    #expect(controller.presentation.result?.text == opened.presentation.result?.text)
    #expect(
      controller.layout.resultPane?.content.blocks == opened.layout.resultPane?.content.blocks)
    #expect(controller.presentation.currentBlock == opened.presentation.currentBlock)
    #expect(controller.saving != nil)
  }

  @Test func windowTellsVoiceOverOnceTheLinesAreThere() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }
    controller.window?.orderFront(nil)
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }

    await waiting.fill(with: .success(try await SampleDiffs.greeting()))
    #expect(announcements == ["Files compared. 3 Changes"])
  }

  @Test func windowThatFillsBeforeItShowsTellsVoiceOverNothing() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }

    await waiting.fill(with: .success(try await SampleDiffs.greeting()))
    #expect(announcements.isEmpty)
  }

  @Test func windowThatWaitsCountsNothingYetAndShowsNoFormatOfTheResult() async throws {
    for (files, kind) in [(Self.files, Session.Kind.diff), (Self.mergeFiles, .merge)] {
      let controller = try await waiting(for: files, kind: kind).controller
      defer { controller.window?.close() }
      #expect(controller.toolbarCount == .waiting)
      if kind == .merge {
        #expect(controller.layout.resultHeader?.format == nil)
      }
    }
  }

  @Test func mergeThatFailsAfterItShowsSaysSoUnderItsNameAndEndsUnresolved() async throws {
    let waiting = try await waiting(for: Self.mergeFiles, kind: .merge)
    let controller = waiting.controller
    controller.window?.orderFront(nil)
    var announcements: [String] = []
    controller.presentation.announce = { announcements.append($0) }
    var outcomes: [SessionOutcome] = []
    controller.onFinish = { outcomes.append($0) }

    await waiting.fill(with: .failure(.filesTooLarge))
    #expect(announcements == ["Seamerge can’t merge “Settings.swift”"])
    #expect(controller.toolbarCount == .nothing)
    #expect(!controller.canPerform(.nextConflict))
    controller.window?.close()
    #expect(outcomes == [.cancelled])
  }

  @Test func windowSaysWhyInPlaceOfTheLinesWhenTheComparisonFails() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    defer { controller.window?.close() }

    await waiting.fill(with: .failure(.filesTooLarge))
    #expect(!controller.waitsForComparison)
    #expect(controller.phase.unavailable?.reason == .filesTooLarge)
    #expect(!controller.canPerform(.nextChange))
  }

  @Test func closingAMergeThatWaitsLeavesItUnsavedAndAComparisonSeen() async throws {
    for (files, kind, expected) in [
      (Self.mergeFiles, Session.Kind.merge, SessionOutcome.cancelled), (Self.files, .diff, .saved),
    ] {
      let controller = try await waiting(for: files, kind: kind).controller
      var outcomes: [SessionOutcome] = []
      controller.onFinish = { outcomes.append($0) }
      controller.window?.close()
      #expect(outcomes == [expected])
    }
  }

  @Test func windowClosedWhileItWaitsStaysEmptyWhenTheComparisonComes() async throws {
    let waiting = try await waiting()
    let controller = waiting.controller
    controller.window?.close()

    await waiting.fill(with: .success(try await SampleDiffs.greeting()))
    #expect(controller.presentation.changes.blocks.isEmpty)
  }

  @Test func comparisonReadyWithinTheWaitOpensTheWindowFilled() async throws {
    let session = try await SampleDiffs.greeting()
    let ready = PendingComparison { .success(session) }
    let outcome = await SessionWindowController.outcome(of: ready, within: 30)
    #expect(try outcome?.get().blocks == session.blocks)

    let (never, continuation) = AsyncStream.makeStream(
      of: Result<Session, SessionLoadingError>.self)
    let slow = PendingComparison {
      var iterator = never.makeAsyncIterator()
      return await iterator.next() ?? .failure(.comparisonFailed)
    }
    #expect(await SessionWindowController.outcome(of: slow, within: 0.01) == nil)
    continuation.finish()
  }

  @Test func comparisonReadyWithinTheWaitFillsTheWindowBeforeItReturns() async throws {
    let files = try SampleFiles()
    let session = try await SampleDiffs.greeting()
    let opened = try Windows.controller(for: session)
    defer { opened.window?.close() }
    let controller = try await SessionWindowController.open(
      Session.Inputs(
        a: SessionFile(url: try files.file("old.txt"), label: "Greeting.swift"),
        b: SessionFile(url: try files.file("new.txt"), label: "Greeting.swift")),
      kind: .diff, mode: .windowDefault, context: SessionContext(), undoManager: UndoManager(),
      settings: .private(), waitingAtMost: 30
    ) { _, _ in session }
    defer { controller.window?.close() }

    #expect(!controller.waitsForComparison)
    #expect(controller.presentation.currentBlock == opened.presentation.currentBlock)
    for (filled, shown) in zip(Windows.panes(of: controller), Windows.panes(of: opened)) {
      #expect(filled.documentView.string == shown.documentView.string)
    }
  }

  @Test func comparisonLongerThanTheWaitReturnsTheWindowWithoutLines() async throws {
    let files = try SampleFiles()
    let (outcomes, continuation) = AsyncStream.makeStream(of: Session.self)
    defer { continuation.finish() }
    let controller = try await SessionWindowController.open(
      Session.Inputs(
        a: SessionFile(url: try files.file("old.txt"), label: "Greeting.swift"),
        b: SessionFile(url: try files.file("new.txt"), label: "Greeting.swift")),
      kind: .diff, mode: .windowDefault, context: SessionContext(), undoManager: UndoManager(),
      settings: .private(), waitingAtMost: 0
    ) { _, _ throws(SessionLoadingError) in
      var iterator = outcomes.makeAsyncIterator()
      guard let session = await iterator.next() else { throw .comparisonFailed }
      return session
    }
    defer { controller.window?.close() }

    #expect(controller.waitsForComparison)
    #expect(controller.layout.sourcePane(.b)?.documentView.string.isEmpty == true)
  }

  @Test func openedWindowShowsTheComparisonOfItsFiles() async throws {
    let files = try SampleFiles()
    let (old, new) = (try files.file("old.txt"), try files.file("new.txt"))
    let controller = try await SessionWindowController.openDiff(
      old: SessionFile(url: old, label: "old.txt"), new: SessionFile(url: new, label: "new.txt"),
      mode: .windowDefault, context: SessionContext(), undoManager: UndoManager(),
      settings: .private())
    defer { controller.window?.close() }
    // A comparison this small is ready before the window shows, unless the machine is busy.
    await controller.phase.filling?.value

    #expect(!controller.waitsForComparison)
    #expect(controller.presentation.changes.blocks.count == 1)
    #expect(controller.layout.sourcePane(.b)?.documentView.string == "new.txt")
  }

  @Test func fileThatIsNotTextIsNamedBeforeTheWindowShows() async throws {
    let files = try SampleFiles()
    let image = files.folder.appending(path: "image.png")
    try Data([0, 1, 2, 0, 80, 78, 71]).write(to: image)
    let work = WorkFolder()

    await #expect(throws: SessionLoadingError.binaryFile(image)) {
      _ = try await SessionWindowController.openMerge(
        base: nil, a: SessionFile(url: try files.file("a.txt"), label: "a"),
        b: SessionFile(url: image, label: "b"), mode: .windowDefault,
        context: SessionContext(), undoManager: UndoManager(), settings: .private(),
        workStore: work.store)
    }
    #expect(try work.fileNames.isEmpty)
  }
}
