import AppKit
import MergeModel
import SeamergeUI
import SessionIPC
import Testing

/// When the welcome window appears, and what happens to the files it opens.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppDelegateTests {
  @Test func startWithoutATaskShowsTheWelcomeWindow() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge"])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    await delegate.startWindowTask?.value

    let window = try #require(delegate.welcomeWindowController?.window)
    #expect(window.isVisible)
    #expect(window.title == "Welcome")
    #expect(window.attachedSheet == nil)
    window.close()
    await delegate.coordinator.finish()
  }

  @Test func commandsOfTheFileMenuShowTheWelcomeWindowWithTheirSheet() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let fileMenu = try #require(delegate.mainMenu.menu.items[1].submenu)
    let compare = try #require(fileMenu.items.first { $0.keyEquivalent == "o" })
    #expect(compare.keyEquivalentModifierMask == .command)
    let merge = try #require(fileMenu.items.first { $0.title == "Merge Files…" })

    for (item, title) in [(compare, "Compare Files"), (merge, "Merge Files")] {
      let action = try #require(item.action)
      NSApplication.shared.sendAction(action, to: delegate, from: item)
      let window = try #require(delegate.welcomeWindowController?.window)
      #expect(window.isVisible)
      #expect(window.attachedSheet?.title == title)
    }
    delegate.welcomeWindowController?.close()
  }

  @Test func startByTheHelperShowsNoWindow() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(delegate.welcomeWindowController == nil)
    #expect(FileManager.default.fileExists(atPath: sandbox.socketURL.path(percentEncoded: false)))
    await delegate.coordinator.finish()
  }

  @Test func clickOnTheDockIconWithoutAWindowShowsTheWelcomeWindow() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])

    #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
    #expect(delegate.welcomeWindowController == nil)
    #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))

    let window = try #require(delegate.welcomeWindowController?.window)
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

    let window = try #require(delegate.welcomeWindowController?.window)
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

  @Test func filesThatCannotBeOpenedFailTheOpeningOfTheWelcomeWindow() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let controller = WelcomeWindowController(
      recentComparisons: delegate.recentComparisons, integrationStore: sandbox.integrationStore)
    let binary = try sandbox.file("image.png", "\u{0}\u{1}PNG\u{0}")
    let merge = FileComparison(
      left: binary, base: try sandbox.file("base.txt"), right: try sandbox.file("mine.txt"))

    await #expect(throws: SessionLoadingError.binaryFile(binary)) {
      try await delegate.welcomeWindowController(controller, open: merge)
    }
    #expect(delegate.coordinator.windowControllers.isEmpty)
    #expect(delegate.recentComparisons.comparisons.isEmpty)
    #expect(sandbox.presenter.errors.isEmpty)
  }

  @Test func appHidesAfterItsLastSessionWindowUnlessTheWelcomeWindowIsOpen() async throws {
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
    delegate.showWelcome()
    last.close()
    #expect(sandbox.presenter.hideCount == 1)
    delegate.welcomeWindowController?.close()
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

  @Test func comparisonOfTwoFilesOpensFromTheWelcomeWindowAndFromOpenRecent() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let comparison = FileComparison(
      left: try sandbox.file("old.txt", "a\n"), right: try sandbox.file("new.txt", "b\n"))
    let controller = WelcomeWindowController(
      recentComparisons: delegate.recentComparisons, integrationStore: sandbox.integrationStore)

    try await delegate.welcomeWindowController(controller, open: comparison)
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

  @Test func comparisonOfTwoFoldersOpensAtOnceAndFromOpenRecentWithAFolderSymbol() async throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let recorder = WindowRecorder()
    delegate.coordinator.delegate = recorder
    let folders = try sandbox.folders()
    let comparison = FileComparison(folders: folders)
    let controller = WelcomeWindowController(
      recentComparisons: delegate.recentComparisons, integrationStore: sandbox.integrationStore)

    try await delegate.welcomeWindowController(controller, open: comparison)
    let first = await recorder.nextOpened()
    #expect(first.collection?.folders == folders)
    #expect(first.window?.title == "Old ↔ New")
    first.close()
    #expect(first.collection?.isDismissed == true)
    delegate.recentComparisons.add(comparison)
    let menu = delegate.recentComparisonsMenu.menu
    delegate.recentComparisonsMenu.menuNeedsUpdate(menu)
    #expect(menu.items[0].image != nil)
    #expect(menu.items[0].title == "Old ↔ New")
    menu.performActionForItem(at: 0)
    let second = await recorder.nextOpened()

    #expect(second.collection?.folders == folders)
    second.close()
  }

  @Test func foldersOnTheDockIconLandInTheOuterFieldsWithoutOpening() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let folders = try sandbox.folders()
    let plain = [folders.left, folders.right].map {
      URL(filePath: $0.path(percentEncoded: false), directoryHint: .notDirectory)
    }

    delegate.application(.shared, open: plain)

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    let fields = fileFields(in: window)
    #expect(fields.map(\.label) == ["Left Folder", "Right Folder"])
    #expect(fields.map(\.value) == [folders.left, folders.right].map(fileFieldValue(of:)))
    #expect(delegate.coordinator.windowControllers.isEmpty)
  }

  @Test func appTakesFilesAndFoldersButIsNeverTheirDefaultApp() throws {
    let app = Bundle(for: AppDelegate.self).bundleURL.deletingLastPathComponent()
      .appending(path: "Seamerge.app")
    let info = try #require(NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")))
    let types = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])

    #expect(
      types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        == ["public.data", "public.folder"])
    for type in types {
      #expect(type["LSHandlerRank"] as? String == "None", "\(type)")
      #expect(type["CFBundleTypeRole"] as? String == "Viewer", "\(type)")
    }
  }

  @Test func settingsOpenFromTheAppMenuOnceAndKeepTheirValuesInTheDefaultsOfTheApp() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let appMenu = try #require(delegate.mainMenu.menu.items.first?.submenu)
    let item = try #require(appMenu.items.first { $0.keyEquivalent == "," })
    #expect(item.action == #selector(AppDelegate.showSettings(_:)))

    delegate.showSettings(item)
    let window = try #require(delegate.settingsWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    #expect(window.title == "General", "the window takes the name of the page in view")
    delegate.showSettings(item)
    #expect(delegate.settingsWindowController?.window === window)

    delegate.settings.tabWidth = 6
    #expect(UserSettings(defaults: sandbox.defaults).tabWidth == 6)
  }

  @Test func keyboardShortcutsOpenFromTheHelpMenuOnce() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let helpMenu = try #require(delegate.mainMenu.menu.items.last?.submenu)
    let item = try #require(helpMenu.items.first { $0.title == "Keyboard Shortcuts" })
    #expect(item.action == #selector(AppDelegate.showKeyboardShortcuts(_:)))

    delegate.showKeyboardShortcuts(item)
    let window = try #require(delegate.shortcutOverviewWindowController?.window)
    defer { window.close() }
    #expect(window.isVisible)
    #expect(window.title == "Keyboard Shortcuts")
    delegate.showKeyboardShortcuts(item)
    #expect(delegate.shortcutOverviewWindowController?.window === window)
  }

  @Test func commandLineToolShowsItsSheetOnTheWelcomeWindowAndIsNamedByWhatItOffers() throws {
    let sandbox = try AppSandbox()
    let delegate = makeDelegate(in: sandbox, arguments: ["Seamerge", HelperLaunch.argument])
    let item = NSMenuItem(
      title: "", action: #selector(AppDelegate.showCommandLineTool(_:)), keyEquivalent: "")
    #expect(delegate.validateMenuItem(item))
    #expect(item.title == "Install Command Line Tool…")

    delegate.showCommandLineTool(item)

    let window = try #require(delegate.welcomeWindowController?.window)
    defer { window.close() }
    let sheet = try #require(window.attachedSheet)
    #expect(window.isVisible)
    #expect(sheet.accessibilityTitle() == "Install the seamerge Command")
    #expect(!delegate.validateMenuItem(item))
    let gitItem = NSMenuItem(
      title: "", action: #selector(AppDelegate.showGitIntegration(_:)), keyEquivalent: "")
    #expect(!delegate.validateMenuItem(gitItem))
    sheet.windowController?.cancelOperation(nil)
    #expect(window.attachedSheet == nil)
    #expect(delegate.validateMenuItem(item))
    #expect(delegate.validateMenuItem(gitItem))

    try FileManager.default.createDirectory(
      at: sandbox.folder.appending(path: "bin"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: sandbox.folder.appending(path: "bin/seamerge"),
      withDestinationURL: Bundle.main.bundleURL.appending(path: "Contents/Helpers/seamerge"))

    #expect(delegate.validateMenuItem(item))
    #expect(item.title == "Remove Command Line Tool…")
  }

  private func makeDelegate(in sandbox: AppSandbox, arguments: [String]) -> AppDelegate {
    AppDelegate(
      arguments: arguments, defaults: sandbox.defaults, socketURL: sandbox.socketURL,
      collectionCache: sandbox.collectionCache, workStore: sandbox.workStore,
      presenter: sandbox.presenter,
      integrationStore: sandbox.integrationStore,
      commandLineTool: sandbox.commandLineTool,
      makeSoftwareUpdater: { _ in SoftwareUpdaterDouble() }, bundle: sandbox.bundle,
      updateServices: {})
  }
}
