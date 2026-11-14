import AppKit
import MergeModel
import SeamergeUI
import SessionIPC
import Testing

/// When the window Compare Files appears, and what happens to the files it opens.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppDelegateTests {
  @Test func startWithoutATaskShowsCompareFiles() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge"])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    let window = try #require(delegate.compareFilesWindowController?.window)
    #expect(window.isVisible)
    #expect(window.title == "Compare Files")
    window.close()
    await delegate.coordinator.finish()
  }

  @Test func startByTheHelperShowsNoWindow() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(delegate.compareFilesWindowController == nil)
    #expect(FileManager.default.fileExists(atPath: sandbox.socketURL.path(percentEncoded: false)))
    await delegate.coordinator.finish()
  }

  @Test func clickOnTheDockIconWithoutAWindowShowsCompareFiles() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
    #expect(delegate.compareFilesWindowController == nil)
    #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))

    let window = try #require(delegate.compareFilesWindowController?.window)
    #expect(window.isVisible)
    window.close()
    #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
  }

  @Test func filesOnTheDockIconLandInTheFields() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let files = [try sandbox.file("a.txt"), try sandbox.file("o.txt"), try sandbox.file("b.txt")]

    #expect(delegate.openFiles(files))
    #expect(!delegate.openFiles(files + [try sandbox.file("d.txt")]))

    let window = try #require(delegate.compareFilesWindowController?.window)
    #expect(window.isVisible)
    window.close()
  }

  @Test func recentMergeOpensFromOpenRecentAndComesFirst() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let merge = FileComparison(
      left: try sandbox.file("theirs.txt", "a\nb\n"), base: try sandbox.file("base.txt", "a\n"),
      right: try sandbox.file("mine.txt", "a\nc\n"))
    let other = FileComparison(
      left: try sandbox.file("x.txt"), base: try sandbox.file("y.txt"),
      right: try sandbox.file("z.txt"))
    delegate.recentComparisons.add(merge)
    delegate.recentComparisons.add(other)
    let menu = delegate.recentComparisonsMenu.menu
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    #expect(menu.items.map(\.title) == [other.title, merge.title, "", "Clear Menu"])
    #expect(delegate.recentComparisonsMenu.validateMenuItem(menu.items[1]))
    let added = NotificationCenter.default.notifications(
      named: RecentComparisons.didChangeNotification, object: delegate.recentComparisons)

    menu.performActionForItem(at: 1)
    let controller = await recorder.nextOpened()
    for await _ in added {
      break
    }

    #expect(controller.window?.title == "mine.txt")
    #expect(delegate.recentComparisons.comparisons == [merge, other])
    controller.close()
  }

  @Test func filesThatCannotBeOpenedFailTheOpeningOfTheWindowCompareFiles() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let controller = CompareFilesWindowController(
      recentComparisons: delegate.recentComparisons, integrationStore: sandbox.integrationStore)
    let binary = try sandbox.file("image.png", "\u{0}\u{1}PNG\u{0}")
    let merge = FileComparison(
      left: binary, base: try sandbox.file("base.txt"), right: try sandbox.file("mine.txt"))

    await #expect(throws: SessionLoadingError.binaryFile(binary)) {
      try await delegate.compareFilesWindowController(controller, open: merge)
    }
    #expect(delegate.coordinator.windowControllers.isEmpty)
    #expect(delegate.recentComparisons.comparisons.isEmpty)
    #expect(sandbox.presenter.errors.isEmpty)
  }

  @Test func appHidesAfterItsLastSessionWindowUnlessCompareFilesIsOpen() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let recorder = WindowRecorder()
    let merge = FileComparison(
      left: try sandbox.file("theirs.txt", "a\nb\n"), base: try sandbox.file("base.txt", "a\n"),
      right: try sandbox.file("mine.txt", "a\nc\n"))
    try await delegate.coordinator.open(merge)
    try await delegate.coordinator.open(merge)
    let windows = delegate.coordinator.windowControllers
    #expect(windows.count == 2)
    #expect(sandbox.presenter.hideCount == 0)

    windows[0].close()
    #expect(sandbox.presenter.hideCount == 0)
    windows[1].close()
    #expect(sandbox.presenter.hideCount == 1)

    delegate.coordinator.delegate = recorder
    try await delegate.coordinator.open(merge)
    let last = await recorder.nextOpened()
    delegate.coordinator.delegate = delegate
    delegate.showCompareFiles(nil)
    last.close()
    #expect(sandbox.presenter.hideCount == 1)
    delegate.compareFilesWindowController?.close()
  }

  @Test func commandsTakeTheKeysAndNamesOfTheWindowInFront() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let merge = FileComparison(
      left: try sandbox.file("theirs.txt", "a\nb\n"), base: try sandbox.file("base.txt", "a\n"),
      right: try sandbox.file("mine.txt", "a\nc\n"))
    try await delegate.coordinator.open(merge)
    let window = try #require(delegate.coordinator.windowControllers.first?.window)
    let nextConflict = try #require(delegate.mainMenu.commandItems[.nextConflict])
    delegate.mainMenu.update(for: .diff)
    #expect(delegate.mainMenu.leaveUnresolvedItem.title == "Skip Remaining Files")

    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

    #expect(delegate.mainMenu.leaveUnresolvedItem.title == "Leave Unresolved")
    #expect(MainMenuTests.keys(of: nextConflict) == "⌥⌘↓")
    window.close()
  }

  @Test func listeningThatFailsAtLaunchIsToldInWords() async throws {
    let sandbox = try AppSandbox()
    let otherCopy = try SessionServer(socketURL: sandbox.socketURL)
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(
      sandbox.presenter.errors.compactMap { $0 as? ListeningError } == [.anotherCopyIsRunning])
    #expect(sandbox.presenter.messages == ["Another copy of Seamerge is already running."])
    #expect(ListeningError.anotherCopyIsRunning.recoverySuggestion?.isEmpty == false)
    withExtendedLifetime(otherCopy) {}
  }

  @Test func reasonsTheAppCannotListenNameNoGit() {
    let errors: [ListeningError] = [
      .anotherCopyIsRunning, .socketPathTooLong, .socketFolderNotPrivate(path: "/tmp/x"),
      .socketUnavailable,
    ]
    for error in errors {
      let texts = [error.errorDescription, error.recoverySuggestion].compactMap(\.self)
      #expect(texts.count == 2 && texts.allSatisfy { !$0.contains("Git") }, "\(error)")
    }
  }

  @Test func clearMenuEmptiesTheRecentComparisons() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    delegate.recentComparisons.add(
      FileComparison(
        left: try sandbox.file("a.txt"), base: try sandbox.file("o.txt"),
        right: try sandbox.file("b.txt")))
    let menu = delegate.recentComparisonsMenu.menu
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    let clear = try #require(menu.items.last)
    #expect(delegate.recentComparisonsMenu.validateMenuItem(clear))

    menu.performActionForItem(at: menu.items.count - 1)

    #expect(delegate.recentComparisons.comparisons.isEmpty)
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    #expect(menu.items.map(\.title) == ["Clear Menu"])
    #expect(!delegate.recentComparisonsMenu.validateMenuItem(menu.items[0]))
  }

  @Test func comparisonOfTwoFilesOpensFromTheWindowCompareFilesAndFromOpenRecent() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let comparison = FileComparison(
      left: try sandbox.file("old.txt", "a\n"), right: try sandbox.file("new.txt", "b\n"))
    let controller = CompareFilesWindowController(
      recentComparisons: delegate.recentComparisons, integrationStore: sandbox.integrationStore)

    try await delegate.compareFilesWindowController(controller, open: comparison)
    let first = await recorder.nextOpened()
    first.close()
    delegate.recentComparisons.add(comparison)
    let menu = delegate.recentComparisonsMenu.menu
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    #expect(delegate.recentComparisonsMenu.validateMenuItem(menu.items[0]))
    menu.performActionForItem(at: 0)
    let second = await recorder.nextOpened()

    #expect(first.window?.title == "old.txt ↔ new.txt")
    #expect(second.window?.title == "old.txt ↔ new.txt")
    second.close()
  }

  private func makeDelegate(in sandbox: AppSandbox, arguments: [String]) -> AppDelegate {
    AppDelegate(
      arguments: arguments, defaults: sandbox.defaults, socketURL: sandbox.socketURL,
      collectionCache: sandbox.collectionCache, presenter: sandbox.presenter,
      integrationStore: sandbox.integrationStore)
  }
}
