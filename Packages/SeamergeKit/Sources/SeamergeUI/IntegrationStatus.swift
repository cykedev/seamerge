import Foundation
import GitSupport

/// Whether Git and Tower open this copy of Seamerge, and what setting it up would change.
struct IntegrationStatus: Sendable, Equatable {
  /// What Git says.
  enum GitStatus: Sendable, Equatable {
    /// Git is not installed.
    case notInstalled

    /// Git is installed, and its configuration says `state`.
    case installed(GitIntegrationState)
  }

  /// What Tower says, if it is installed.
  enum TowerStatus: Sendable, Equatable {
    /// Tower lists this copy.
    case added

    /// Tower does not list this copy, and adding it would make `change`.
    case notAdded(TowerConfiguration.Change)

    /// Tower's list of tools cannot be read, so nothing is added to it.
    case unreadable
  }

  /// What Git says.
  var git: GitStatus

  /// What Tower says, or `nil` if Tower is not installed.
  var tower: TowerStatus?

  /// What an earlier setup from the app remembered, or `nil` if there was none.
  var backup: GitBackup?

  /// Why Git cannot be pointed at this copy, or `nil` if it can.
  var problem: AppLocation.Problem?

  /// The commands that set up Git, for the user to read or copy.
  var commands: [String]

  /// The state of Git's configuration, or `nil` if Git is not installed.
  var gitState: GitIntegrationState? {
    guard case .installed(let state) = git else { return nil }
    return state
  }

  /// Whether Git uses this copy for both merges and diffs, so that the sheet offers to remove it.
  var isSetUp: Bool {
    gitState?.merge == .seamerge && gitState?.diff == .seamerge
  }

  /// The line at the bottom of the window Compare Files: whether Git opens Seamerge.
  var line: String {
    guard let state = gitState else {
      return String(
        localized:
          "Git isn’t installed. Install the Xcode Command Line Tools to use Seamerge with Git.",
        bundle: .module, comment: "Compare Files: the line about Git when Git is missing.")
    }
    if state.merge.isMoved || state.diff.isMoved {
      return String(
        localized: "Git points to a copy of Seamerge that has moved.", bundle: .module,
        comment: "Compare Files: the line about Git when it uses another copy of the app.")
    }
    switch (state.merge == .seamerge, state.diff == .seamerge) {
    case (true, true):
      return String(
        localized: "✓ Git uses Seamerge for merge and diff", bundle: .module,
        comment: "Compare Files: the line about Git when it uses the app for both.")
    case (true, false):
      return String(
        localized: "✓ Git uses Seamerge for merge.", bundle: .module,
        comment: "Compare Files: the line about Git when it uses the app for merges only.")
    case (false, true):
      return String(
        localized: "✓ Git uses Seamerge for diff.", bundle: .module,
        comment: "Compare Files: the line about Git when it uses the app for diffs only.")
    case (false, false):
      return String(
        localized: "Git doesn’t use Seamerge yet.", bundle: .module,
        comment: "Compare Files: the line about Git when it uses the app for neither.")
    }
  }

  /// Whether the line offers the sheet: Git is installed and does not use this copy for both
  /// merges and diffs, or Tower is installed and does not list it.
  var offersSetUp: Bool {
    gitState != nil && (!isSetUp || offersAddingToTower)
  }

  /// Whether Tower is installed and does not list this copy, so that the sheet offers to add it.
  var offersAddingToTower: Bool {
    if case .notAdded? = tower { true } else { false }
  }
}

extension GitIntegrationState.Tool {
  /// Whether the tool is a copy of Seamerge other than this one.
  var isMoved: Bool {
    if case .movedSeamerge = self { true } else { false }
  }

  /// The name of the tool for the sheet, or `nil` for no tool and for this copy.
  var replacedName: String? {
    switch self {
    case .none, .seamerge: nil
    case .other(let name): name
    case .movedSeamerge(let helper):
      String(
        localized: "Seamerge at \(Self.appPath(ofHelper: helper))", bundle: .module,
        comment:
          "Set Up Git Integration: another copy of the app, such as Seamerge at /Volumes/A.app."
      )
    }
  }

  /// The path of the app whose helper is at `helper`, or the helper's own path if it is not in
  /// the bundle of an app.
  private static func appPath(ofHelper helper: String) -> String {
    let suffix = "/Contents/Helpers/seamerge"
    return helper.hasSuffix(suffix) ? String(helper.dropLast(suffix.count)) : helper
  }
}
