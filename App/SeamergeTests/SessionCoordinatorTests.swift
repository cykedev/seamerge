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

    #expect(try await outcome.value == .closed(.cancelled))
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test(arguments: [false, true])
  func mergeWaitsForGitOnlyWhereTheRequestSaysSo(isRunByGit: Bool) async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    guard case .merge(var merge) = try sandbox.mergeRequest() else {
      Issue.record("The sandbox asks for a merge")
      return
    }
    merge.isRunByGit = isRunByGit
    let outcome = perform(.merge(merge), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    #expect(controller.context.waitingCaller == (isRunByGit ? .git : .commandLine))
    controller.window?.close()

    #expect(try await outcome.value == .closed(.cancelled))
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
      #expect(try await outcome.value == .closed(.cancelled))
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
      #expect(try await outcome.value == .closed(.cancelled))
    }
  }

  @Test func quittingClosesEveryWindowAndTellsEachHelperThatItWasCancelled() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    // A comparison that closes reports success, which would let Git go on to the next file.
    let outcomes = [
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
      perform(try sandbox.comparisonRequest(), at: sandbox.socketURL),
    ]
    let windows = [await recorder.nextOpened(), await recorder.nextOpened()]

    await coordinator.finish()

    for outcome in outcomes {
      #expect(try await outcome.value == .closed(.cancelled))
    }
    #expect(windows.allSatisfy { $0.window?.isVisible == false })
    #expect(coordinator.windowControllers.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: sandbox.socketURL.path(percentEncoded: false)))
  }

  @Test func comparisonFromGitOpensAWindowAndClosingItReportsSaved() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcome = perform(try sandbox.comparisonRequest(), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(window.isVisible)
    #expect(window.title == "src/story.txt")
    #expect(window.subtitle == "File 2 of 3")
    #expect(coordinator.kind(of: window) == .diff)
    window.close()

    #expect(try await outcome.value == .closed(.saved))
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func skippingTheRemainingFilesReportsCancelled() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let outcome = perform(try sandbox.comparisonRequest(), at: sandbox.socketURL)
    let controller = await recorder.nextOpened()

    NSApplication.shared.sendAction(
      SessionCommand.skipRemainingFiles.action, to: controller, from: nil)

    #expect(try await outcome.value == .closed(.cancelled))
    #expect(controller.window?.isVisible == false)
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func mergeOfAFileThatIsNotTextOpensAWindowThatCanLeaveItUnresolved() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let binary = try sandbox.file("image.png", "\u{0}\u{1}\u{2}PNG\u{0}")
    let request = SessionRequest.merge(
      .init(
        base: nil, local: try sandbox.file("local.txt"), remote: binary,
        output: try sandbox.file("out.txt")))
    let outcome = perform(request, at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    NSApplication.shared.sendAction(
      SessionCommand.leaveUnresolved.action, to: controller, from: nil)

    #expect(try await outcome.value == .closed(.cancelled))
    #expect(sandbox.presenter.errors.isEmpty)
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test(arguments: [true, false])
  func comparisonThatCannotBeShownStillOpensAWindowAndLetsGitGoOn(isBinary: Bool) async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let right =
      isBinary
      ? try sandbox.file("logo_REMOTE.png", "\u{0}\u{1}\u{2}PNG\u{0}")
      : sandbox.folder.appending(path: "missing.txt")
    let request = SessionRequest.diff(
      SessionRequest.Diff(
        left: try sandbox.file("logo_LOCAL.png", "a\n"), right: right, displayPath: "logo.png",
        context: SessionRequest.DiffContext(
          filePosition: SessionRequest.FilePosition(number: 1, count: 2))))
    let outcome = perform(request, at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(window.title == "logo.png")
    #expect(sandbox.presenter.errors.isEmpty)
    #expect(!controller.validateUserInterfaceItem(menuItem(for: .nextChange)))
    #expect(controller.validateUserInterfaceItem(menuItem(for: .skipRemainingFiles)))
    window.close()

    #expect(try await outcome.value == .closed(.saved))
    await coordinator.finish()
  }

  /// An item of the main menu that sends the action of `command`.
  private func menuItem(for command: SessionCommand) -> NSMenuItem {
    NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
  }

  @Test func filesFromTheWelcomeWindowOpenAMergeInTheirRoles() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, settings: sandbox.settings,
      presentError: sandbox.presentError)
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

  @Test func twoFilesFromTheWelcomeWindowOpenAComparisonInTheirRoles() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, settings: sandbox.settings,
      presentError: sandbox.presentError)
    coordinator.delegate = recorder
    let comparison = FileComparison(
      left: try sandbox.file("old.txt", "a\nb\n"), right: try sandbox.file("new.txt", "a\nc\n"))

    try await coordinator.open(comparison)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(window.title == "old.txt ↔ new.txt")
    #expect(controller.comparisonOptions.mode == .windowDefault)
    #expect(coordinator.kind(of: window) == .diff)
    controller.close()
  }

  @Test func filesOpenInTheComparisonModeOfTheSettings() async throws {
    let sandbox = try AppSandbox()
    sandbox.settings.comparisonMode = .exact
    let recorder = WindowRecorder()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, settings: sandbox.settings,
      presentError: sandbox.presentError)
    coordinator.delegate = recorder

    try await coordinator.open(
      FileComparison(
        left: try sandbox.file("theirs.txt", "a\nb\n"), base: try sandbox.file("base.txt", "a\n"),
        right: try sandbox.file("mine.txt", "a \nc\n")))

    let controller = await recorder.nextOpened()
    #expect(controller.comparisonOptions.mode == .exact)
    controller.close()
  }

  @Test func filesFromTheWindowThatCannotBeOpenedThrowWithTheFile() async throws {
    let sandbox = try AppSandbox()
    let coordinator = SessionCoordinator(
      socketURL: sandbox.socketURL, settings: sandbox.settings,
      presentError: sandbox.presentError)
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
