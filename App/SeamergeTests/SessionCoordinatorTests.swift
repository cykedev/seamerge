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
  @Test func requestOpensAWindowTitledAfterTheMergedFile() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let session = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    let window = try #require(controller.window)
    #expect(window.isVisible)
    #expect(window.title == "story.txt")
    #expect(window.representedURL == sandbox.folder.appending(path: "story.txt"))
    #expect(controller.comparisonOptions.mode == .windowDefault)
    window.close()

    #expect(coordinator.windowControllers.isEmpty)
    session.cancel()
    await coordinator.stop()
  }

  @Test func everyWindowHasAnUndoManagerOfItsOwn() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let sessions = [
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
      perform(try sandbox.mergeRequest(), at: sandbox.socketURL),
    ]

    let first = await recorder.nextOpened()
    let second = await recorder.nextOpened()

    let undoManagers = [first, second].compactMap { $0.window?.undoManager }
    #expect(undoManagers.count == 2)
    #expect(undoManagers[0] !== undoManagers[1])
    for controller in [first, second] {
      controller.close()
    }
    for session in sessions {
      session.cancel()
    }
    await coordinator.stop()
  }

  @Test func comparisonOfTwoFilesIsRefusedForNow() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let request = SessionRequest.diff(
      .init(left: try sandbox.file("old.txt"), right: try sandbox.file("new.txt")))

    await #expect(throws: SessionError.rejected(.unsupportedRequest)) {
      try await perform(request, at: sandbox.socketURL).value
    }
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.stop()
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
    await coordinator.stop()
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
