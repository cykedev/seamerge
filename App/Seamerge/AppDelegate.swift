import AppKit
import MergeModel
import SeamergeUI
import os

/// The delegate of the app: builds the main menu, starts the coordinator of the sessions, and
/// shows the window Compare Files where nothing else is to be done.
///
/// The window Compare Files appears when the app starts without a task, when the Dock icon is
/// clicked while no window is open, with File > Compare Files…, and with files dropped on the
/// Dock icon. It does not appear when the helper starts the app, nor after the helper's last
/// window; then the app hides, so that the terminal is in front again.
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

  /// The window Compare Files, once it has appeared.
  private(set) var compareFilesWindowController: CompareFilesWindowController?

  /// Whether the helper started the app to hand over a session.
  private let isLaunchedForSession: Bool

  /// Shows alerts and hides the app.
  private let presenter: any AppPresenter

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "App")

  /// Creates the delegate of an app started with `arguments`, which keeps its recent
  /// comparisons in `defaults`, listens for the helper at `socketURL`, and shows alerts and hides
  /// with `presenter`.
  init(
    arguments: [String], defaults: UserDefaults, socketURL: URL, presenter: any AppPresenter
  ) {
    isLaunchedForSession = arguments.contains(HelperLaunch.argument)
    self.presenter = presenter
    recentComparisons = RecentComparisons(defaults: defaults)
    recentComparisonsMenu = RecentComparisonsMenu(recentComparisons: recentComparisons)
    mainMenu = MainMenu(openRecentMenu: recentComparisonsMenu.menu)
    coordinator = SessionCoordinator(socketURL: socketURL) { [weak presenter] error in
      presenter?.present(error)
    }
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
    let controller = CompareFilesWindowController(recentComparisons: recentComparisons)
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

  /// Gives the commands the keys and names of the kind of window in front.
  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    mainMenu.update(for: coordinator.kind(of: window) ?? .merge)
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
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows {
      showCompareFiles(nil)
    }
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    if !openFiles(urls) {
      Self.logger.notice("The window Compare Files takes up to three files and no folders")
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Closes every session window, which tells each waiting helper that its session was
  /// cancelled, before the app quits.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await coordinator.finish()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
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
