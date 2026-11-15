import AppKit
import Sparkle

/// Sparkle's updater with its standard windows, except that the question whether to check
/// automatically waits while the app holds it.
@MainActor
final class SparkleUpdater: SoftwareUpdater {
  private let updater: SPUUpdater
  private let userDriver: PatientUserDriver

  /// Creates the updater of the app with `delegate` as the delegate of the updater and of its
  /// windows; its question waits while `holdsQuestion` says so.
  init(delegate: Updater, holdsQuestion: @escaping @MainActor () -> Bool) {
    userDriver = PatientUserDriver(
      hostBundle: .main, delegate: delegate, holdsQuestion: holdsQuestion)
    updater = SPUUpdater(
      hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: delegate)
  }

  var automaticallyChecksForUpdates: Bool {
    get { updater.automaticallyChecksForUpdates }
    set { updater.automaticallyChecksForUpdates = newValue }
  }

  var canCheckForUpdates: Bool {
    updater.canCheckForUpdates
  }

  var isHoldingQuestion: Bool {
    userDriver.gate.isHolding
  }

  func startUpdater() throws {
    try updater.start()
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }

  func observeAutomaticChecks(_ onChange: @escaping @MainActor () -> Void) -> AnyObject {
    updater.observe(\.automaticallyChecksForUpdates) { _, _ in
      // Sparkle changes its settings on the main thread only.
      MainActor.assumeIsolated { onChange() }
    }
  }
}

/// Sparkle's standard windows, whose question whether to check automatically waits in a
/// ``QuestionGate`` until Sparkle is asked to bring its update session to the front.
private final class PatientUserDriver: SPUStandardUserDriver {
  /// Holds the question while the app says so.
  let gate: QuestionGate

  init(
    hostBundle: Bundle, delegate: any SPUStandardUserDriverDelegate,
    holdsQuestion: @escaping @MainActor () -> Bool
  ) {
    gate = QuestionGate(holds: holdsQuestion)
    super.init(hostBundle: hostBundle, delegate: delegate)
  }

  override func show(
    _ request: SPUUpdatePermissionRequest,
    reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    gate.pass { super.show(request, reply: reply) }
  }

  /// Shows the question if it waits; Sparkle calls this for Check for Updates… while its question
  /// is open, so that the question comes to the front.
  override func showUpdateInFocus() {
    if !gate.release() {
      super.showUpdateInFocus()
    }
  }
}

/// Shows a question at once, or keeps it while `holds` says so until it is released.
@MainActor
final class QuestionGate {
  private let holds: @MainActor () -> Bool
  private var heldQuestion: (() -> Void)?

  /// Whether a question waits.
  var isHolding: Bool {
    heldQuestion != nil
  }

  /// Creates a gate that keeps a question while `holds` says so.
  init(holds: @escaping @MainActor () -> Bool) {
    self.holds = holds
  }

  /// Shows the question with `show` at once, unless the gate holds it.
  func pass(_ show: @escaping () -> Void) {
    if holds() {
      heldQuestion = show
    } else {
      show()
    }
  }

  /// Shows the question that waits, if one does, and tells whether one did.
  func release() -> Bool {
    guard let heldQuestion else { return false }
    self.heldQuestion = nil
    heldQuestion()
    return true
  }
}
