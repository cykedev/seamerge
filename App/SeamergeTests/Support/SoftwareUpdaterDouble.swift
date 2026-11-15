import Foundation

/// Stands in for Sparkle's updater and records what the app asks of it.
@MainActor
final class SoftwareUpdaterDouble: SoftwareUpdater {
  var automaticallyChecksForUpdates = false {
    didSet { onAutomaticChecksChange?() }
  }
  var canCheckForUpdates = true
  var isHoldingQuestion = false
  private(set) var startCount = 0
  private(set) var checkCount = 0
  private var onAutomaticChecksChange: (@MainActor () -> Void)?

  func startUpdater() {
    startCount += 1
  }

  func checkForUpdates() {
    checkCount += 1
  }

  func observeAutomaticChecks(_ onChange: @escaping @MainActor () -> Void) -> AnyObject {
    onAutomaticChecksChange = onChange
    return NSObject()
  }
}
