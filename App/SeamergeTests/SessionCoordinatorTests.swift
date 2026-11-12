import AppKit
import GitSupport
import MergeModel
import SeamergeUI
import SessionIPC
import Testing

/// The coordinator of the sessions, driven through a real socket by a client in the test, as the
/// helper drives it.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SessionCoordinatorTests {
  @Test func requestOpensAWindowAndClosingItReportsCancelled() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(window.isVisible)
    #expect(window.title == "story.txt")
    #expect(window.representedURL == sandbox.folder.appending(path: "story.txt"))
    window.close()

    #expect(try await outcome.value == .cancelled)
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func everySessionIsComparedInTheModeOfTheWindow() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()

    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(controller.window?.subtitle.contains("exactly") == false)
    controller.close()
    _ = try await outcome.value
    await coordinator.finish()
  }

  @Test func helperThatGoesAwayIsToldToTheWindow() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    let heightWhileGitWaits = try #require(resultHeaderHeight(in: window))

    outcome.cancel()
    await coordinator.waitUntilIdle()

    window.contentView?.layoutSubtreeIfNeeded()
    let heightAfterwards = try #require(resultHeaderHeight(in: window))
    #expect(heightAfterwards > heightWhileGitWaits)
    #expect(window.isVisible)
    #expect(coordinator.windowControllers.count == 1)
    window.close()
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func twelveSessionsInARowAreServedByTheSameApp() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    var windows: [SessionWindowController] = []

    for _ in 1...12 {
      let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
      let controller = await recorder.nextOpened()
      windows.append(controller)
      controller.close()
      #expect(try await outcome.value == .cancelled)
    }

    #expect(Set(windows.map(ObjectIdentifier.init)).count == 12)
    #expect(recorder.changeCount == 24)
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func everyWindowHasAnUndoManagerOfItsOwn() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcomes = [
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
    ]

    let first = await recorder.nextOpened()
    let second = await recorder.nextOpened()

    let undoManagers = [first, second].compactMap { $0.window?.undoManager }
    #expect(undoManagers.count == 2)
    #expect(undoManagers[0] !== undoManagers[1])
    await coordinator.finish()
    for outcome in outcomes {
      #expect(try await outcome.value == .cancelled)
    }
  }

  @Test func quittingClosesEveryWindowAndTellsEachHelper() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcomes = [
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
    ]
    let windows = [await recorder.nextOpened(), await recorder.nextOpened()]

    await coordinator.finish()

    for outcome in outcomes {
      #expect(try await outcome.value == .cancelled)
    }
    #expect(windows.allSatisfy { $0.window?.isVisible == false })
    #expect(coordinator.windowControllers.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: sandbox.socketURL.path(percentEncoded: false)))
  }

  @Test func comparisonOfTwoFilesIsRefusedForNow() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let request = SessionRequest.diff(
      .init(left: try sandbox.file("old.txt"), right: try sandbox.file("new.txt")))

    await #expect(throws: SessionError.rejected(.unsupportedRequest)) {
      try await perform(request, at: sandbox.socketURL).value
    }
    #expect(!coordinator.canOpen(.diff))
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func fileThatIsNotTextIsShownAsAnErrorAndCancelsTheSession() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let binary = try sandbox.file("image.png", "\u{0}\u{1}\u{2}PNG\u{0}")
    let request = SessionRequest.merge(
      .init(
        base: nil, local: try sandbox.file("local.txt"), remote: binary,
        output: try sandbox.file("out.txt")))

    #expect(try await perform(request, at: sandbox.socketURL).value == .cancelled)

    #expect(
      sandbox.presenter.errors.compactMap { $0 as? SessionLoadingError } == [.binaryFile(binary)])
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func filesFromTheWindowCompareFilesOpenAMergeInTheirRoles() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, presentError: sandbox.presentError)
    coordinator.delegate = recorder
    let merge = FileComparison(
      left: try sandbox.file("theirs.txt", "a\nb\n"), base: try sandbox.file("base.txt", "a\n"),
      right: try sandbox.file("mine.txt", "a\nc\n"))

    try await coordinator.open(merge)

    let controller = await recorder.nextOpened()
    #expect(controller.window?.title == "mine.txt")
    #expect(controller.window?.representedURL == nil)
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(coordinator.kind(of: try #require(controller.window)) == .merge)
    controller.close()
  }

  @Test func filesFromTheWindowThatCannotBeOpenedThrowWithTheFile() async throws {
    let sandbox = try AppSandbox()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, presentError: sandbox.presentError)
    let binary = try sandbox.file("image.png", "\u{0}\u{1}PNG\u{0}")
    let merge = FileComparison(
      left: binary, base: try sandbox.file("base.txt"), right: try sandbox.file("mine.txt"))

    await #expect(throws: SessionLoadingError.binaryFile(binary)) {
      try await coordinator.open(merge)
    }
    #expect(coordinator.windowControllers.isEmpty)
    #expect(sandbox.presenter.errors.isEmpty)
  }

  @Test func namesFromGitReachTheWindowAsTheHelperSentThem() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let request = SessionRequest.MergeContext(
      operation: .rebase,
      remote: .init(
        name: .commit(abbreviatedHash: "1a2b3c4", subject: "Fix it", branch: "feature"),
        role: .yourCommit,
        commit: .init(
          hash: "1a2b3c4d5e", abbreviatedHash: "1a2b3c4", subject: "Fix it", authorName: "Ada",
          authorDate: date)),
      local: .init(name: .reference("main"), role: .rebaseTarget),
      base: .init(name: .stash),
      rebaseProgress: .init(targetName: .reference("main"), commitNumber: 2, commitCount: 3),
      remainingConflictedFileCount: 4)

    let context = GitContext(request, hasCommonAncestor: false)

    #expect(context.operation == .rebase)
    #expect(
      context.remote.name
        == .commit(abbreviatedHash: "1a2b3c4", subject: "Fix it", branch: "feature"))
    #expect(context.remote.role == .yourCommit)
    #expect(
      context.remote.commit
        == CommitDetails(
          hash: "1a2b3c4d5e", abbreviatedHash: "1a2b3c4", authorName: "Ada", authorDate: date,
          subject: "Fix it"))
    #expect(context.local == MergeSide(name: .reference("main"), role: .rebaseTarget))
    #expect(context.base == MergeSide(name: .stash))
    #expect(!context.hasCommonAncestor)
    #expect(
      context.rebaseProgress
        == RebaseProgress(targetName: .reference("main"), commitNumber: 2, commitCount: 3))
    #expect(context.remainingConflictedFileCount == 4)
  }
}
