import AppKit

/// The delegate of the app, which builds the main menu.
@MainActor
final class AppDelegate: NSObject {
  /// The menu bar.
  let mainMenu = MainMenu()
}

extension AppDelegate: NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    let application = NSApplication.shared
    application.mainMenu = mainMenu.menu
    application.windowsMenu = mainMenu.windowsMenu
    application.helpMenu = mainMenu.helpMenu
    application.servicesMenu = mainMenu.servicesMenu
  }
}
