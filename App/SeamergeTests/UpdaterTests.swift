import AppKit
import SessionIPC
import Sparkle
import Testing

/// Updates with Sparkle: that the updater starts with the app, that its windows wait while a
/// session window is in front, that the app never relaunches or quits for an update while a helper
/// waits, and the one setting.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct UpdaterTests {
  @Test func updaterStartsWithTheAppAlsoWhenGitOpensIt() async throws {
    let sandbox = try AppSandbox()
    let softwareUpdater = SoftwareUpdaterDouble()
    let delegate = makeDelegate(in: sandbox, softwareUpdater: softwareUpdater)

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(softwareUpdater.startCount == 1)
    await delegate.coordinator.finish()
  }

  @Test func questionWaitsWhileAWindowOfGitOrItsSheetIsInFront() async throws {
    let sandbox = try AppSandbox()
    let softwareUpdater = SoftwareUpdaterDouble()
    let delegate = makeDelegate(in: sandbox, softwareUpdater: softwareUpdater)
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
    let window = try #require(await recorder.nextOpened().window)
    delegate.coordinator.delegate = delegate
    softwareUpdater.isHoldingQuestion = true

    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    let alert = NSAlert()
    alert.beginSheetModal(for: window) { _ in }
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
    #expect(alert.window.sheetParent === window)
    #expect(softwareUpdater.checkCount == 0)
    window.endSheet(alert.window)

    delegate.showCompareFiles(nil)
    let compareFiles = try #require(delegate.compareFilesWindowController?.window)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: compareFiles)
    #expect(softwareUpdater.checkCount == 1)

    window.close()
    compareFiles.close()
    _ = try await outcome.value
    await delegate.coordinator.finish()
  }

  @Test func questionHeldWhileASessionWindowIsInFrontShowsOnceWhenReleased() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let updater = Updater(helpers: coordinator) { _ in SoftwareUpdaterDouble() }
    let gate = QuestionGate { updater.holdsQuestion }
    var showCount = 0
    updater.windowDidBecomeKey(showsSession: true)

    gate.pass { showCount += 1 }
    #expect(showCount == 0)
    #expect(gate.isHolding)

    updater.windowDidBecomeKey(showsSession: false)
    #expect(gate.release())
    #expect(!gate.release())
    #expect(showCount == 1)
    #expect(!gate.isHolding)
    gate.pass { showCount += 1 }
    #expect(showCount == 2)
    await coordinator.finish()
  }

  @Test func versionFoundWhileASessionWindowIsInFrontWaitsUntilAnotherWindowIs() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let softwareUpdater = SoftwareUpdaterDouble()
    let updater = Updater(helpers: coordinator) { _ in softwareUpdater }
    updater.windowDidBecomeKey(showsSession: true)

    let showsAtOnce = updater.standardUserDriverShouldHandleShowingScheduledUpdate(
      SUAppcastItem.empty(), andInImmediateFocus: true)
    updater.versionWillShow(atOnce: showsAtOnce)

    #expect(!showsAtOnce)
    #expect(softwareUpdater.checkCount == 0)
    updater.windowDidBecomeKey(showsSession: false)
    #expect(softwareUpdater.checkCount == 1)
    updater.windowDidBecomeKey(showsSession: false)
    #expect(softwareUpdater.checkCount == 1)
    await coordinator.finish()
  }

  @Test func versionFoundBeforeAnyWindowWasInFrontWaits() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let updater = Updater(helpers: coordinator) { _ in SoftwareUpdaterDouble() }

    #expect(
      !updater.standardUserDriverShouldHandleShowingScheduledUpdate(
        SUAppcastItem.empty(), andInImmediateFocus: true))
    updater.windowDidBecomeKey(showsSession: false)
    #expect(
      updater.standardUserDriverShouldHandleShowingScheduledUpdate(
        SUAppcastItem.empty(), andInImmediateFocus: false))
    await coordinator.finish()
  }

  @Test func relaunchWaitsForEveryHelperAndTheUpdateInstallsOnlyOnQuit() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let updater = Updater(helpers: coordinator) { _ in SoftwareUpdaterDouble() }
    let merge = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
    let mergeWindow = await recorder.nextOpened()
    let comparison = perform(try sandbox.comparisonRequest(), at: sandbox.socketURL)
    let comparisonWindow = await recorder.nextOpened()
    var installCount = 0

    let postpones = updater.updater(
      sparkleUpdater(), shouldPostponeRelaunchForUpdate: SUAppcastItem.empty(),
      untilInvokingBlock: { installCount += 1 })

    #expect(postpones)
    mergeWindow.window?.close()
    #expect(try await merge.value == .closed(.cancelled))
    #expect(updater.postponesRelaunch)
    comparisonWindow.window?.close()
    _ = try await comparison.value
    await coordinator.waitUntilIdle()
    await Task.yield()
    #expect(installCount == 0)
    #expect(!updater.postponesRelaunch)
    await coordinator.finish()
  }

  @Test func sparklesRequestToQuitIsRefusedOnlyWhileAHelperWaits() async throws {
    let sandbox = try AppSandbox()
    let recorder = WindowRecorder()
    let coordinator = try sandbox.startCoordinator(recorder: recorder)
    let updater = Updater(helpers: coordinator) { _ in SoftwareUpdaterDouble() }
    let agent = "org.sparkle-project.Sparkle.Updater"
    #expect(!updater.refusesQuit(requestedBy: agent))

    let outcome = perform(try sandbox.mergeRequest(), at: sandbox.socketURL)
    let controller = await recorder.nextOpened()

    #expect(updater.refusesQuit(requestedBy: agent))
    #expect(!updater.refusesQuit(requestedBy: nil))
    #expect(!updater.refusesQuit(requestedBy: "com.apple.dock"))
    controller.window?.close()
    _ = try await outcome.value
    await coordinator.waitUntilIdle()
    #expect(!updater.refusesQuit(requestedBy: agent))
    await coordinator.finish()
  }

  @Test func settingOfAutomaticChecksIsTheUpdatersInBothDirections() async throws {
    let sandbox = try AppSandbox()
    let coordinator = try sandbox.startCoordinator(recorder: WindowRecorder())
    let softwareUpdater = SoftwareUpdaterDouble()
    let updater = Updater(helpers: coordinator) { _ in softwareUpdater }
    #expect(!updater.checksAutomatically)

    updater.checksAutomatically = true
    #expect(softwareUpdater.automaticallyChecksForUpdates)

    // As when the user answers Sparkle's question with Don't Check.
    softwareUpdater.automaticallyChecksForUpdates = false
    #expect(!updater.checksAutomatically)
    await coordinator.finish()
  }

  @Test func checkForUpdatesChecksAndWorksWhileNoCheckRuns() throws {
    let sandbox = try AppSandbox()
    let softwareUpdater = SoftwareUpdaterDouble()
    let delegate = makeDelegate(in: sandbox, softwareUpdater: softwareUpdater)
    let appMenu = try #require(delegate.mainMenu.menu.items.first?.submenu)
    let item = try #require(appMenu.items.first { $0.title == "Check for Updates…" })
    #expect(item.action == #selector(AppDelegate.checkForUpdates(_:)))
    #expect(delegate.validateMenuItem(item))

    delegate.checkForUpdates(item)

    #expect(softwareUpdater.checkCount == 1)
    softwareUpdater.canCheckForUpdates = false
    #expect(!delegate.validateMenuItem(item))
  }

  private func makeDelegate(
    in sandbox: AppSandbox, softwareUpdater: SoftwareUpdaterDouble
  ) -> AppDelegate {
    AppDelegate(
      arguments: ["Seamerge", HelperLaunch.argument], defaults: sandbox.defaults,
      socketURL: sandbox.socketURL, collectionCache: sandbox.collectionCache,
      presenter: sandbox.presenter, integrationStore: sandbox.integrationStore,
      makeSoftwareUpdater: { _ in softwareUpdater })
  }

  /// An updater of Sparkle that is never started, for the calls of its delegate.
  private func sparkleUpdater() -> SPUUpdater {
    SPUUpdater(
      hostBundle: .main, applicationBundle: .main,
      userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil), delegate: nil)
  }
}
