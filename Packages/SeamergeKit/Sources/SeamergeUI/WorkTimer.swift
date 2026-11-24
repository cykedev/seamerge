import Foundation

/// Runs an action once after a delay, on the main actor: the pace at which a merge window keeps
/// its work on disk.
@MainActor
protocol WorkTimer {
  /// Calls `action` once, `delay` from now.
  func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
}

/// The timer of the app, which fires on the main run loop, also while a menu is open or the
/// user drags.
struct RunLoopWorkTimer: WorkTimer {
  func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
    let timer = Timer(timeInterval: delay / .seconds(1), repeats: false) { _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated { action() }
    }
    RunLoop.main.add(timer, forMode: .common)
  }
}
