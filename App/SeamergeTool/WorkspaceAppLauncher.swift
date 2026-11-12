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

  func openApp() async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.arguments = [HelperLaunch.argument]
    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }
}
