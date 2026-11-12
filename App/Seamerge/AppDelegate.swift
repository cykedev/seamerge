import AppKit
import MergeModel
import os

/// The delegate of the app: builds the main menu and starts the coordinator of the sessions.
///
/// After the last session window, the app hides, so that the terminal is in front again.
@MainActor
final class AppDelegate: NSObject {
  /// Opens a window for each session.
  let coordinator: SessionCoordinator

  /// The menu bar.
  let mainMenu = MainMenu()

  /// Shows alerts and hides the app.
  private let presenter: any AppPresenter

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "App")

  /// Creates the delegate of an app that listens for the helper at `socketURL`, and shows alerts
  /// and hides with `presenter`.
  init(socketURL: URL, presenter: any AppPresenter) {
    self.presenter = presenter
    coordinator = SessionCoordinator(socketURL: socketURL) { [weak presenter] error in
      presenter?.present(error)
    }
    super.init()
    coordinator.delegate = self
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification,
      object: nil)
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
  /// Hides the app after its last session window has closed, so that the terminal that waited is
  /// in front again.
  func sessionCoordinatorDidChangeWindows(_ coordinator: SessionCoordinator) {
    if coordinator.windowControllers.isEmpty {
      presenter.hide()
    }
  }
}
