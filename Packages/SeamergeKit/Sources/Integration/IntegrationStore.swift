import AppKit
public import Foundation
package import GitSupport
import os

/// Reads and writes the settings that make Git and Tower open the app.
package protocol IntegrationStore: Sendable {
  /// What the settings say now.
  ///
  /// - Throws: ``IntegrationFailure`` if Git's configuration cannot be read.
  func status() async throws(IntegrationFailure) -> IntegrationStatus

  /// Makes Git use the app for merges and diffs, and, with `addingToTower`, adds it to Tower.
  ///
  /// - Throws: ``IntegrationFailure`` if a setting cannot be written; what was written by then
  ///   is taken back.
  func setUp(addingToTower: Bool) async throws(IntegrationFailure)

  /// Adds the app to Tower, where Git uses it already.
  ///
  /// - Throws: ``IntegrationFailure`` if Tower's list of tools cannot be read or written.
  func addToTower() async throws(IntegrationFailure)

  /// Takes back what setting up wrote, in Git and in Tower.
  ///
  /// - Throws: ``IntegrationFailure`` if a setting cannot be written.
  func remove() async throws(IntegrationFailure)
}

/// Why the settings of Git or Tower could not be read or written.
package enum IntegrationFailure: LocalizedError, Equatable {
  /// Git is not installed.
  case gitMissing

  /// Git's configuration could not be read or written.
  case git(GitError)

  /// Tower's list of tools could not be read or written.
  case tower(TowerConfigurationError)

  package var errorDescription: String? {
    switch self {
    case .gitMissing, .git:
      String(
        localized: "Git couldn’t save the settings.", bundle: .module,
        comment: "Set Up Git Integration: writing Git's configuration failed.")
    case .tower:
      String(
        localized: "Tower’s list of tools couldn’t be changed.", bundle: .module,
        comment: "Set Up Git Integration: writing Tower's list of tools failed.")
    }
  }

  package var failureReason: String? {
    switch self {
    case .gitMissing:
      String(
        localized: "Git isn’t installed.", bundle: .module,
        comment: "Set Up Git Integration: the reason of a failure when Git is missing.")
    case .git(.failed(_, _, let message)) where !message.isEmpty: message
    case .git(.launchFailed(_, let reason)): reason
    case .git: nil
    case .tower(.unreadable(_, let reason)), .tower(.cannotWrite(_, let reason)): reason
    }
  }
}

/// The settings of this Mac: the global Git configuration of the user, Tower's folder in the
/// user's home folder, and the memory of the setup in the user defaults.
public struct SystemIntegrationStore: IntegrationStore {
  private let bundle: URL
  private let environment: [String: String]
  private let tower: TowerConfiguration?
  /// The suite of the user defaults that remember the setup, `nil` for the standard ones;
  /// `UserDefaults` itself cannot cross into the background.
  private let defaultsSuite: String?

  private static let backupKey = "GitIntegrationBackup"
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "Integration")

  /// Creates the store of the app whose bundle is at `bundle`, which writes Tower's settings
  /// into the home folder `home` if Tower is installed, runs Git in `environment`, and remembers
  /// its setup in the standard user defaults.
  public init(
    bundle: URL, home: URL, environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let isTowerInstalled =
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.fournova.Tower3") != nil
    self.init(
      bundle: bundle, environment: environment,
      towerFolder: isTowerInstalled ? TowerConfiguration.folder(inHome: home) : nil,
      defaultsSuite: nil)
  }

  /// Creates the store of the app at `bundle`, whose Git runs in `environment`, with Tower's
  /// folder of tools at `towerFolder`, or without Tower if it is `nil`, which remembers its setup
  /// in the user defaults of `defaultsSuite`.
  init(bundle: URL, environment: [String: String], towerFolder: URL?, defaultsSuite: String?) {
    self.bundle = bundle
    self.environment = environment
    self.defaultsSuite = defaultsSuite
    tower = towerFolder.map {
      TowerConfiguration(helper: AppLocation.helper(inBundle: bundle), folder: $0)
    }
  }

  @concurrent package func status() async throws(IntegrationFailure) -> IntegrationStatus {
    let location = AppLocation.current(bundle: bundle)
    let commands = GitConfiguration(helper: location.helper).commands
    var status = IntegrationStatus(
      git: .notInstalled, tower: nil, backup: storedBackup(), problem: location.problem,
      commands: commands)
    if let git = Git.installed(environment: environment) {
      do {
        status.git = .installed(try GitIntegration(helper: location.helper, git: git).state())
      } catch {
        throw .git(error)
      }
    }
    if let tower {
      do {
        status.tower = try tower.change().map(IntegrationStatus.TowerStatus.notAdded) ?? .added
      } catch {
        Self.logger.error("Cannot read Tower's list of tools: \(String(describing: error))")
        status.tower = .unreadable
      }
    }
    return status
  }

  @concurrent package func setUp(addingToTower: Bool) async throws(IntegrationFailure) {
    let integration = try gitIntegration()
    let towerToAdd = addingToTower ? tower : nil
    let earlierTower: TowerConfiguration.Snapshot?
    do {
      earlierTower = try towerToAdd?.snapshot()
      try towerToAdd?.add()
    } catch {
      throw .tower(error)
    }
    do {
      store(try integration.setUp(keeping: storedBackup()))
    } catch {
      do {
        // An entry that was there before, such as one of another copy, comes back as it was.
        if let towerToAdd, let earlierTower {
          try towerToAdd.restore(earlierTower)
        }
      } catch let undoError {
        Self.logger.error(
          "Cannot put Tower's list of tools back: \(String(describing: undoError))")
      }
      throw .git(error)
    }
  }

  @concurrent package func addToTower() async throws(IntegrationFailure) {
    do {
      try tower?.add()
    } catch {
      throw .tower(error)
    }
  }

  @concurrent package func remove() async throws(IntegrationFailure) {
    let integration = try gitIntegration()
    do {
      try integration.remove(restoring: storedBackup())
    } catch {
      throw .git(error)
    }
    defaults.removeObject(forKey: Self.backupKey)
    do {
      // Only the entry of this copy is taken back, as the sheet says.
      if let tower, try tower.change() == nil {
        try tower.remove()
      }
    } catch {
      throw .tower(error)
    }
  }

  private func gitIntegration() throws(IntegrationFailure) -> GitIntegration {
    guard let git = Git.installed(environment: environment) else { throw .gitMissing }
    return GitIntegration(helper: AppLocation.helper(inBundle: bundle), git: git)
  }

  /// The user defaults that remember the setup.
  private var defaults: UserDefaults {
    defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

  private func storedBackup() -> GitBackup? {
    guard let data = defaults.data(forKey: Self.backupKey) else { return nil }
    do {
      return try JSONDecoder().decode(GitBackup.self, from: data)
    } catch {
      Self.logger.error("Cannot read the remembered Git settings: \(String(describing: error))")
      return nil
    }
  }

  private func store(_ backup: GitBackup) {
    do {
      defaults.set(try JSONEncoder().encode(backup), forKey: Self.backupKey)
    } catch {
      Self.logger.error("Cannot remember the replaced Git settings: \(String(describing: error))")
    }
  }
}
