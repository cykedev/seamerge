import AppKit
import SeamergeUI
import Sparkle
import os

/// What the app uses of Sparkle's updater, so that tests can stand in for it.
@MainActor
protocol SoftwareUpdater: AnyObject {
  /// Whether the updater asks once a day whether a new version exists.
  var automaticallyChecksForUpdates: Bool { get set }

  /// Whether a check for a new version can start now.
  var canCheckForUpdates: Bool { get }

  /// Whether the question whether to check automatically waits to be brought to the front.
  var isHoldingQuestion: Bool { get }

  /// Starts the updater: asks whether to check automatically if it is time to, and from then on
  /// checks as the user chose.
  ///
  /// - Throws: Why the updater cannot start, such as a feed or key missing from the app.
  func startUpdater() throws

  /// Looks for a new version and shows the result, or brings the question or a found version to
  /// the front.
  func checkForUpdates()

  /// Calls `onChange` whenever ``automaticallyChecksForUpdates`` changes, until the returned
  /// observation is released.
  func observeAutomaticChecks(_ onChange: @escaping @MainActor () -> Void) -> AnyObject
}

/// Finds and installs new versions of the app with Sparkle, with the consent of the user and
/// without disturbing a merge or a call of Git.
///
/// The updater starts with the app, so that the daily check runs also when only Git opens it.
/// Every window of Sparkle that the app does not ask for, the question whether to check
/// automatically and a version that the daily check found, waits until a window other than a
/// session window is in front, such as the welcome window. Installing goes through the usual
/// quitting of the app, which asks about unsaved changes and tells every waiting helper how its
/// session ended. While a helper waits, the app does not relaunch: the update installs when the
/// app quits.
@MainActor
@Observable
final class Updater: NSObject, AutomaticUpdateSetting {
  /// Whether the app asks once a day whether a new version exists, as Sparkle keeps it.
  var checksAutomatically: Bool {
    get { automaticChecks }
    set { softwareUpdater?.automaticallyChecksForUpdates = newValue }
  }

  /// Whether Check for Updates… can start a check now.
  var canCheckForUpdates: Bool {
    softwareUpdater?.canCheckForUpdates ?? false
  }

  /// Whether a window other than a session window became key last, so that windows of Sparkle
  /// may show; not before any window has.
  @ObservationIgnored private(set) var isQuiet = false

  /// The mirror of Sparkle's setting, which the window Settings observes.
  private var automaticChecks = false

  // Set in init right after super.init(), since Sparkle's updater takes this object as its
  // delegate when it is made.
  @ObservationIgnored private var softwareUpdater: (any SoftwareUpdater)?
  @ObservationIgnored private var automaticChecksObservation: AnyObject?
  @ObservationIgnored private var hasWaitingVersion = false
  @ObservationIgnored private let helpers: SessionCoordinator

  /// The bundle identifier of Sparkle's agent, which asks the app to quit for installing.
  private static let sparkleAgent = "org.sparkle-project.Sparkle.Updater"

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "Updates")

  /// Creates an updater that keeps the app running while `helpers` serves a helper, around the
  /// updater that `makeSoftwareUpdater` makes for it.
  init(
    helpers: SessionCoordinator,
    makeSoftwareUpdater: @MainActor (Updater) -> any SoftwareUpdater = Updater.sparkle
  ) {
    self.helpers = helpers
    super.init()
    let softwareUpdater = makeSoftwareUpdater(self)
    self.softwareUpdater = softwareUpdater
    automaticChecks = softwareUpdater.automaticallyChecksForUpdates
    automaticChecksObservation = softwareUpdater.observeAutomaticChecks { [weak self] in
      guard let self, let softwareUpdater = self.softwareUpdater else { return }
      automaticChecks = softwareUpdater.automaticallyChecksForUpdates
    }
  }

  /// Sparkle's updater with its standard windows, whose question waits while `updater` holds it;
  /// not started yet.
  static func sparkle(for updater: Updater) -> any SoftwareUpdater {
    SparkleUpdater(delegate: updater) { [weak updater] in updater?.holdsQuestion ?? true }
  }

  /// Whether Sparkle's question whether to check automatically waits, which it does until a
  /// window other than a session window is in front.
  var holdsQuestion: Bool {
    !isQuiet
  }

  /// Starts checking as the user chose.
  func start() {
    do {
      try softwareUpdater?.startUpdater()
    } catch {
      Self.logger.error("The updater cannot start: \(String(describing: error))")
    }
  }

  /// Learns which kind of window is in front: a session window, or another one such as Compare
  /// Files, where the question or a found version that waits comes to the front.
  func windowDidBecomeKey(showsSession: Bool) {
    isQuiet = !showsSession
    guard isQuiet, let softwareUpdater else { return }
    if hasWaitingVersion || softwareUpdater.isHoldingQuestion {
      hasWaitingVersion = false
      softwareUpdater.checkForUpdates()
    }
  }

  /// Looks for a new version at once and shows the result.
  func checkForUpdates() {
    softwareUpdater?.checkForUpdates()
  }

  /// Whether the relaunch after installing waits, which it does while a helper is served; the
  /// update then installs when the app quits.
  var postponesRelaunch: Bool {
    helpers.isServingHelper
  }

  /// Whether the app refuses to quit for the app with `bundleIdentifier`, which it does when
  /// Sparkle's agent asks while a helper is served.
  ///
  /// Sparkle asks the postponing delegate only once per update; when the user chooses Install
  /// and Relaunch again, its agent asks the app to quit without asking first.
  func refusesQuit(requestedBy bundleIdentifier: String?) -> Bool {
    bundleIdentifier == Self.sparkleAgent && helpers.isServingHelper
  }

  /// Learns that Sparkle found a new version and shows it at once, or leaves it waiting until
  /// another window than a session window is in front.
  func versionWillShow(atOnce: Bool) {
    hasWaitingVersion = !atOnce
  }
}

extension Updater: SPUUpdaterDelegate {
  /// Postpones the relaunch while a helper is served and never invokes `installHandler`, so that
  /// Sparkle installs the update when the app quits, after every helper has its answer.
  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    postponesRelaunch
  }
}

extension Updater: @MainActor SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  /// Shows a version that the daily check found at once only while the app is quiet; otherwise
  /// it waits until a window other than a session window is in front.
  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    isQuiet
  }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    versionWillShow(atOnce: handleShowingUpdate)
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    hasWaitingVersion = false
  }

  func standardUserDriverWillFinishUpdateSession() {
    hasWaitingVersion = false
  }
}
