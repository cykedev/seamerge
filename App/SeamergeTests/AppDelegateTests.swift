import AppKit
import MergeModel
import SessionIPC
import Testing

/// What the delegate of the app does at launch and when a window comes to the front.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppDelegateTests {
  @Test func commandsTakeTheKeysAndNamesOfTheWindowInFront() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox)
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    try delegate.coordinator.start()
    let session = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
    let window = try #require(await recorder.nextOpened().window)
    let nextConflict = try #require(delegate.mainMenu.commandItems[.nextConflict])
    delegate.mainMenu.update(for: .diff)
    #expect(delegate.mainMenu.leaveUnresolvedItem.title == "Skip Remaining Files")

    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

    #expect(delegate.mainMenu.leaveUnresolvedItem.title == "Leave Unresolved")
    #expect(MainMenuTests.keys(of: nextConflict) == "⌥⌘↓")
    window.close()
    session.cancel()
    await delegate.coordinator.stop()
  }

  @Test func listeningThatFailsAtLaunchIsToldInWords() async throws {
    let sandbox = try AppSandbox()
    let otherCopy = try SessionServer(socketURL: sandbox.socketURL)
    let delegate = makeDelegate(in: sandbox)

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(
      sandbox.presenter.errors.compactMap { $0 as? ListeningError } == [.anotherCopyIsRunning])
    #expect(sandbox.presenter.messages == ["Another copy of Seamerge is already running."])
    #expect(ListeningError.anotherCopyIsRunning.recoverySuggestion?.isEmpty == false)
    withExtendedLifetime(otherCopy) {}
  }

  private func makeDelegate(in sandbox: AppSandbox) -> AppDelegate {
    AppDelegate(socketURL: sandbox.socketURL, presenter: sandbox.presenter)
  }
}
