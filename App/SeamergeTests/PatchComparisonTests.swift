import AppKit
import SeamergeUI
import SessionIPC
import Testing

/// A patch that the helper hands to the app through a real socket: the window it opens, when the
/// helper hears back, where the copy lies and when it goes.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PatchComparisonTests {
  private static let patch = Data(
    """
    diff --git a/notes.txt b/notes.txt
    --- a/notes.txt
    +++ b/notes.txt
    @@ -10,3 +10,3 @@
     nine
    -ten
    +10
     eleven

    """.utf8)

  @Test func helperThatDoesNotWaitHearsBackOnceTheWindowShows() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let reply = perform(
      .patch(SessionRequest.Patch(text: Self.patch, fileName: "change.patch")),
      at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    #expect(try await reply.value == .accepted)
    let window = try #require(controller.window)
    #expect(window.isVisible)
    #expect(window.title == "change.patch")
    #expect(controller.context.patch != nil)
    #expect(try sandbox.keptPatches.count == 1)

    window.close()

    #expect(try sandbox.keptPatches.isEmpty)
    #expect(coordinator.windowControllers.isEmpty)
    await coordinator.finish()
  }

  @Test func helperThatWaitsHearsBackOnceTheWindowCloses() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let reply = perform(
      .patch(SessionRequest.Patch(text: Self.patch, waitsForWindow: true)), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    #expect(controller.window?.title == "Patch")
    controller.window?.close()

    #expect(try await reply.value == .closed(.saved))
    #expect(try sandbox.keptPatches.isEmpty)
    await coordinator.finish()
  }

  @Test func windowOfAPatchStaysOpenOnceTheHelperHasEnded() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let reply = perform(.patch(SessionRequest.Patch(text: Self.patch)), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    _ = try await reply.value

    #expect(controller.window?.isVisible == true)
    controller.window?.close()
    await coordinator.finish()
  }

  @Test func patchNeverJoinsTheRecentComparisons() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let reply = perform(.patch(SessionRequest.Patch(text: Self.patch)), at: sandbox.socketURL)

    let controller = await recorder.nextOpened()
    _ = try await reply.value

    #expect(RecentComparisons(defaults: sandbox.defaults).comparisons.isEmpty)
    controller.window?.close()
    await coordinator.finish()
  }

  @Test func patchTheAppCannotReadIsRefusedWithoutAWindow() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)

    let reply = perform(
      .patch(SessionRequest.Patch(text: Data("--- a\n+++ b\n@@ -1,3 +1 @@\n".utf8))),
      at: sandbox.socketURL)

    await #expect(throws: SessionError.rejected(.unreadablePatch)) { try await reply.value }
    #expect(coordinator.windowControllers.isEmpty)
    #expect(try sandbox.keptPatches.isEmpty)
    #expect(sandbox.presenter.errors.isEmpty)
    await coordinator.finish()
  }

  @Test(arguments: [false, true])
  func patchWhoseCopyCannotBeWrittenIsRefusedAndTheAppSaysWhy(waits: Bool) async throws {
    let sandbox = try AppSandbox()
    // A file in the place of the folder of the copies keeps any copy from being written.
    try Data().write(to: sandbox.folder.appending(path: "Patch"))
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)

    let reply = perform(
      .patch(SessionRequest.Patch(text: Self.patch, waitsForWindow: waits)), at: sandbox.socketURL)

    await #expect(throws: SessionError.rejected(.windowNotOpened)) { try await reply.value }
    #expect(coordinator.windowControllers.isEmpty)
    #expect(sandbox.presenter.errors.count == 1)
    await coordinator.finish()
  }

  @Test func launchClearsOutCopiesOfPatchesThatACrashLeftBehind() async throws {
    let sandbox = try AppSandbox()
    let folder = sandbox.folder.appending(path: "Patch", directoryHint: .isDirectory)
    for (name, age) in [("leftover", -3600.0), ("fresh", 3600.0)] {
      let copy = folder.appending(path: name, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
      try FileManager.default.setAttributes(
        [.creationDate: Date.now.addingTimeInterval(age)], ofItemAtPath: copy.path)
    }
    let delegate = AppDelegate(
      arguments: ["Seamerge", HelperLaunch.argument], defaults: sandbox.defaults,
      socketURL: sandbox.socketURL, collectionCache: sandbox.collectionCache,
      workStore: sandbox.workStore, pasteboard: sandbox.pasteboard,
      pastedTextCache: sandbox.pastedTextCache, patchCache: sandbox.patchCache,
      presenter: sandbox.presenter, integrationStore: sandbox.integrationStore,
      commandLineTool: sandbox.commandLineTool,
      makeSoftwareUpdater: { _ in SoftwareUpdaterDouble() }, bundle: sandbox.bundle,
      updateServices: {})

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    await delegate.clearingCopies?.value

    #expect(try sandbox.keptPatches == ["fresh"])
    await delegate.coordinator.finish()
  }
}
