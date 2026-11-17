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
  /// Opening an app that runs already asks it to reopen, which shows the welcome window;
  /// the session on its way shows its own window instead.
  func openApp() async throws {
    if let running = runningCopy() {
      running.unhide()
      running.activate()
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.arguments = [HelperLaunch.argument]
    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }

  /// Waits until the process of the running copy of the app has ended, at most for `timeout`,
  /// and tells whether it has.
  func waitUntilAppQuits(within timeout: Duration) async -> Bool {
    guard let processID = runningCopy()?.processIdentifier else { return true }
    return await Self.waitUntilProcessEnds(processID, within: timeout)
  }

  /// Waits until the process `processID` has ended, at most for `timeout`, and tells whether it
  /// has.
  ///
  /// The helper has no run loop that would update `NSRunningApplication`, so it watches the
  /// process itself.
  static func waitUntilProcessEnds(_ processID: pid_t, within timeout: Duration) async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      // Both sources and the check below run on one serial queue, so the first answers alone.
      let queue = DispatchQueue(label: "app.eiden.seamerge.helper.quitting")
      let exit = DispatchSource.makeProcessSource(
        identifier: processID, eventMask: .exit, queue: queue)
      let timer = DispatchSource.makeTimerSource(queue: queue)
      let answer: @Sendable (Bool) -> Void = { hasEnded in
        guard !exit.isCancelled else { return }
        exit.cancel()
        timer.cancel()
        continuation.resume(returning: hasEnded)
      }
      exit.setEventHandler { answer(true) }
      timer.setEventHandler { answer(false) }
      let (seconds, attoseconds) = timeout.components
      timer.schedule(
        deadline: .now()
          + .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)))
      exit.activate()
      timer.activate()
      queue.async {
        // A process that ended before the source watched it sends no event.
        if kill(processID, 0) != 0, errno == ESRCH {
          answer(true)
        }
      }
    }
  }

  /// The copy of the app around the helper that runs, if one does.
  private func runningCopy() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle(url: appURL)?.bundleIdentifier ?? ""
    ).first { !$0.isTerminated && $0.bundleURL?.resolvingSymlinksInPath().path == appURL.path }
  }
}
