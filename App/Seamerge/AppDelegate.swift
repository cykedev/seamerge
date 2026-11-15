import AppKit
import MergeModel
import SeamergeUI
import os

/// The delegate of the app: builds the main menu, starts the coordinator of the sessions, and
/// shows the window Compare Files where nothing else is to be done.
///
/// The window Compare Files appears when the app starts without a task, when the Dock icon is
/// clicked while no window is open, with File > Compare Files… and File > Compare Folders…, and
/// with files or folders dropped on the Dock icon. It does not appear when the helper starts the
/// app, nor after the helper's last window; then the app hides, so that the terminal is in front
/// again.
@MainActor
final class AppDelegate: NSObject {
  /// Opens a window for each session.
  let coordinator: SessionCoordinator

  /// The menu bar.
  let mainMenu: MainMenu

  /// The comparisons opened last from the window Compare Files.
  let recentComparisons: RecentComparisons

  /// File > Open Recent.
  let recentComparisonsMenu: RecentComparisonsMenu

  /// The settings of the app, which every session window draws and starts with.
  let settings: UserSettings

  /// Finds and installs new versions of the app.
  let updater: Updater

  /// The window Compare Files, once it has appeared.
  private(set) var compareFilesWindowController: CompareFilesWindowController?

  /// The window Settings, once it has appeared.
  private(set) var settingsWindowController: SettingsWindowController?

  /// The window Keyboard Shortcuts, once it has appeared.
  private(set) var shortcutOverviewWindowController: ShortcutOverviewWindowController?

  /// Whether the helper started the app to hand over a session.
  private let isLaunchedForSession: Bool

  /// Shows alerts and hides the app.
  private let presenter: any AppPresenter

  /// The settings of Git and Tower that the window Compare Files reads and writes.
  private let integrationStore: SystemIntegrationStore

  /// The seamerge command in Terminal, whose sheet the window Compare Files shows.
  private let commandLineTool: CommandLineTool

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "App")

  /// Creates the delegate of an app started with `arguments`, which keeps its settings and
  /// recent comparisons in `defaults`, listens for the helper at `socketURL`, keeps the copies of
  /// collected files in `collectionCache`, shows alerts and hides with `presenter`, sets up Git
  /// and Tower in `integrationStore`, installs the seamerge command with `commandLineTool`, and
  /// updates itself with the updater that `makeSoftwareUpdater` makes.
  init(
    arguments: [String], defaults: UserDefaults, socketURL: URL,
    collectionCache: CollectionCache = .standard, presenter: any AppPresenter,
    integrationStore: SystemIntegrationStore, commandLineTool: CommandLineTool,
    makeSoftwareUpdater: @MainActor (Updater) -> any SoftwareUpdater = Updater.sparkle
  ) {
    isLaunchedForSession = arguments.contains(HelperLaunch.argument)
    self.presenter = presenter
    self.integrationStore = integrationStore
    self.commandLineTool = commandLineTool
    settings = UserSettings(defaults: defaults)
    recentComparisons = RecentComparisons(defaults: defaults)
    recentComparisonsMenu = RecentComparisonsMenu(recentComparisons: recentComparisons)
    mainMenu = MainMenu(openRecentMenu: recentComparisonsMenu.menu)
    coordinator = SessionCoordinator(
      socketURL: socketURL, cache: collectionCache, settings: settings
    ) {
      [weak presenter] error in
      presenter?.present(error)
    }
    updater = Updater(helpers: coordinator, makeSoftwareUpdater: makeSoftwareUpdater)
    super.init()
    coordinator.delegate = self
    recentComparisonsMenu.onOpen = { [weak self] in self?.open($0) }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification,
      object: nil)
  }

  /// Shows the window Compare Files in front.
  @objc func showCompareFiles(_ sender: Any?) {
    compareFiles().showWindow(sender)
  }

  /// Shows the window Compare Files in front, empty, with the open panel for the left folder.
  @objc func showCompareFolders(_ sender: Any?) {
    compareFiles().compareFolders()
  }

  /// Shows the window Settings in front, made the first time it is needed.
  @objc func showSettings(_ sender: Any?) {
    let controller =
      settingsWindowController ?? SettingsWindowController(settings: settings, updates: updater)
    settingsWindowController = controller
    controller.showWindow(sender)
  }

  /// Looks for a new version at once and shows the result.
  @objc func checkForUpdates(_ sender: Any?) {
    updater.checkForUpdates()
  }

  /// Shows the window Keyboard Shortcuts in front, made the first time it is needed with the
  /// shortcuts of the kind of session window in front.
  @objc func showKeyboardShortcuts(_ sender: Any?) {
    let controller =
      shortcutOverviewWindowController
      ?? ShortcutOverviewWindowController(
        kind: NSApp.mainWindow.flatMap { coordinator.kind(of: $0) } ?? .merge)
    shortcutOverviewWindowController = controller
    controller.showWindow(sender)
  }

  /// Shows the window Compare Files and on it the sheet Set Up Git Integration.
  @objc func showGitIntegration(_ sender: Any?) {
    compareFiles().showGitIntegration(sender)
  }

  /// Shows the window Compare Files and on it the sheet that installs, updates or removes the
  /// seamerge command.
  @objc func showCommandLineTool(_ sender: Any?) {
    compareFiles().showCommandLineTool(commandLineTool)
  }

  /// Puts `urls` in the fields of the window Compare Files and shows it, and tells whether the
  /// window took them.
  @discardableResult
  func openFiles(_ urls: [URL]) -> Bool {
    let took = compareFiles().fill(with: urls)
    showCompareFiles(nil)
    return took
  }

  /// The window Compare Files, made the first time it is needed.
  private func compareFiles() -> CompareFilesWindowController {
    if let compareFilesWindowController {
      return compareFilesWindowController
    }
    let controller = CompareFilesWindowController(
      recentComparisons: recentComparisons, integrationStore: integrationStore)
    controller.delegate = self
    compareFilesWindowController = controller
    return controller
  }

  /// Opens a session for `comparison` from File > Open Recent and puts it first among the recent
  /// comparisons once its window shows; otherwise says why.
  private func open(_ comparison: FileComparison) {
    Task {
      do {
        try await coordinator.open(comparison)
        recentComparisons.add(comparison)
      } catch {
        presenter.present(error)
      }
    }
  }

  /// Gives the commands the keys and names of the kind of window in front, and tells the updater
  /// whether a session window is in front.
  ///
  /// A sheet or a child window that becomes key belongs to the window it hangs on.
  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard var window = notification.object as? NSWindow else { return }
    while let owner = window.sheetParent ?? window.parent {
      window = owner
    }
    let kind = coordinator.kind(of: window)
    mainMenu.update(for: kind ?? .merge)
    updater.windowDidBecomeKey(showsSession: kind != nil)
  }

  /// The bundle identifier of the app that sent the request to quit that is being handled, if
  /// another app sent it.
  private var senderOfQuitRequest: String? {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
      let sender = event.attributeDescriptor(forKeyword: keySenderPIDAttr)
    else { return nil }
    return NSRunningApplication(processIdentifier: sender.int32Value)?.bundleIdentifier
  }
}

extension AppDelegate: NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    let application = NSApplication.shared
    application.mainMenu = mainMenu.menu
    application.windowsMenu = mainMenu.windowsMenu
    application.helpMenu = mainMenu.helpMenu
    application.servicesMenu = mainMenu.servicesMenu
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      try coordinator.start()
    } catch {
      Self.logger.error("Cannot listen for the helper: \(String(describing: error))")
      presenter.present(ListeningError(error))
    }
    if !isLaunchedForSession {
      showCompareFiles(nil)
    }
    updater.start()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows {
      showCompareFiles(nil)
    }
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    if !openFiles(urls) {
      Self.logger.notice("The window Compare Files takes up to three files or two folders")
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Asks for each merge with unsaved changes whether to save it, then closes every session
  /// window, which tells each waiting helper how its session ended, before the app quits; a
  /// window the user keeps open keeps the app running.
  ///
  /// Sparkle's request to quit for installing is refused while a helper waits.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if updater.refusesQuit(requestedBy: senderOfQuitRequest) {
      return .terminateCancel
    }
    Task {
      guard await coordinator.closeUnsavedWindowsAskingFirst() else {
        sender.reply(toApplicationShouldTerminate: false)
        return
      }
      await coordinator.finish()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

extension AppDelegate: NSMenuItemValidation {
  /// Set Up Git Integration… works while Git is not known to be missing and its sheet is not
  /// shown, Install Command Line Tool… while no sheet hangs on the window Compare Files, and is
  /// called Remove Command Line Tool… once the command of this copy is installed; Check for
  /// Updates… works while no check runs; the other commands of the app always work.
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(showGitIntegration(_:)):
      compareFilesWindowController?.validateUserInterfaceItem(menuItem) ?? true
    case #selector(showCommandLineTool(_:)):
      validateCommandLineTool(menuItem)
    case #selector(checkForUpdates(_:)):
      updater.canCheckForUpdates
    default:
      true
    }
  }
}

extension AppDelegate {
  /// Names the item of the seamerge command by what it offers, and tells whether it works.
  private func validateCommandLineTool(_ menuItem: NSMenuItem) -> Bool {
    menuItem.title =
      commandLineTool.isInstalled
      ? MainMenu.Titles.removeCommandLineTool : MainMenu.Titles.installCommandLineTool
    return compareFilesWindowController?.canShowCommandLineTool(commandLineTool) ?? true
  }
}

extension AppDelegate: SessionCoordinatorDelegate {
  /// Hides the app after its last session window has closed, unless the window Compare Files
  /// is open, so that the terminal that waited is in front again.
  func sessionCoordinatorDidChangeWindows(_ coordinator: SessionCoordinator) {
    let comparesFiles = compareFilesWindowController?.window?.isVisible == true
    if coordinator.windowControllers.isEmpty, !comparesFiles {
      presenter.hide()
    }
  }
}

extension AppDelegate: CompareFilesWindowControllerDelegate {
  func compareFilesWindowController(
    _ controller: CompareFilesWindowController, open comparison: FileComparison
  ) async throws {
    try await coordinator.open(comparison)
  }
}
