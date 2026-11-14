import AppKit
import SeamergeCLI

/// Starts the app the helper is part of, or brings it to the front, through the workspace.
struct WorkspaceAppLauncher: AppLauncher {
  /// The app bundle that holds the helper in `Contents/Helpers/`.
  let appURL: URL

  /// Finds the app around the helper at `executableURL`, also when the helper is started through
  /// a symbolic link.
  init(executableURL: URL) {
    appURL = executableURL.resolvingSymlinksInPath()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// Brings a running copy of the app to the front, or starts it.
  ///
  /// Opening an app that runs already asks it to reopen, which shows the window Compare Files;
  /// the session on its way shows its own window instead.
  func openApp() async throws {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle(url: appURL)?.bundleIdentifier ?? ""
    ).first { $0.bundleURL?.resolvingSymlinksInPath().path == appURL.path }
    if let running {
      running.unhide()
      running.activate()
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.arguments = [HelperLaunch.argument]
    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }
}
