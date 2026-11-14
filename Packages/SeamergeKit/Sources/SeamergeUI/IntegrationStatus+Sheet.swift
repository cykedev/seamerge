import Foundation
import GitSupport

/// The words of the sheet Set Up Git Integration, as they follow from the settings.
extension IntegrationStatus {
  /// The title of the sheet: the offer, or, once Git uses this copy for both, the state.
  var sheetTitle: String {
    isSetUp
      ? String(
        localized: "Git Uses Seamerge for Merge and Diff", bundle: .module,
        comment: "Set Up Git Integration: the title once Git uses the app.")
      : String(
        localized: "Use Seamerge for Git Merges and Diffs", bundle: .module,
        comment: "Set Up Git Integration: the title of the offer.")
  }

  /// What setting up does, or what removing restores.
  var sheetMessage: String {
    guard isSetUp else {
      return String(
        localized: """
          Git opens Seamerge when you run git mergetool or git difftool. This applies to all \
          repositories that don’t set their own tool.
          """, bundle: .module, comment: "Set Up Git Integration: what setting up does.")
    }
    guard let backup else {
      return String(
        localized: """
          Removing takes Seamerge out of Git’s settings. Git’s general settings for tools stay as \
          they are.
          """, bundle: .module,
        comment: "Set Up Git Integration: what removing does after a setup by hand.")
    }
    let tools = backup.restoredTools
    switch (tools.merge, tools.diff) {
    case (nil, nil):
      return String(
        localized: "Removing leaves Git without a merge and diff tool.", bundle: .module,
        comment: "Set Up Git Integration: removing when Git had no tool before.")
    case (let merge?, let diff?) where merge != diff:
      return String(
        localized: "Removing restores: \(merge) for merge and \(diff) for diff.", bundle: .module,
        comment: "Set Up Git Integration: removing brings back two tools, such as Kaleidoscope.")
    default:
      return String(
        localized: "Removing restores: \(tools.merge ?? tools.diff ?? "").", bundle: .module,
        comment: "Set Up Git Integration: removing brings back a tool, such as Kaleidoscope.")
    }
  }

  /// The tools that setting up replaces, or `nil` if it replaces none.
  var replacedTools: String? {
    guard !isSetUp, let state = gitState else { return nil }
    let merge = state.merge.replacedName
    let diff = state.diff.replacedName
    let keepsSettings = [state.merge, state.diff].contains {
      if case .other = $0 { true } else { false }
    }
    let names: String
    switch (merge, diff) {
    case (nil, nil): return nil
    case (let merge?, let diff?) where merge != diff:
      names = String(
        localized: "\(merge) for merge and \(diff) for diff", bundle: .module,
        comment: "Set Up Git Integration: two replaced tools, such as Kaleidoscope for merge…")
    default: names = merge ?? diff ?? ""
    }
    guard keepsSettings else {
      return String(
        localized: "Replaces: \(names).", bundle: .module,
        comment: "Set Up Git Integration: the replaced copy of the app.")
    }
    return String(
      localized: "Replaces: \(names). Its settings stay in place, so you can switch back.",
      bundle: .module, comment: "Set Up Git Integration: the replaced tool, such as Kaleidoscope.")
  }

  /// What setting up changes for other tools too, or `nil` if it changes nothing for them.
  var changedSwitches: String? {
    guard !isSetUp, let switches = gitState?.changedSwitches, !switches.isEmpty else {
      return nil
    }
    if switches.count == 2 {
      return String(
        localized: "Git will no longer ask before opening a tool or keep .orig backup files.",
        bundle: .module, comment: "Set Up Git Integration: both general switches change.")
    }
    return switches.contains(.prompt)
      ? String(
        localized: "Git will no longer ask before opening a tool.", bundle: .module,
        comment: "Set Up Git Integration: Git stops asking before it opens a tool.")
      : String(
        localized: "Git will no longer keep .orig backup files.", bundle: .module,
        comment: "Set Up Git Integration: Git stops keeping backups of merged files.")
  }

  /// Why this copy cannot be set up, or `nil` if it can.
  var problemText: String? {
    switch problem {
    case nil: nil
    case .incomplete:
      String(
        localized: "This copy of Seamerge is incomplete. Download it again.", bundle: .module,
        comment: "Set Up Git Integration: the helper is missing from the app.")
    case .temporaryPlace:
      String(
        localized: "Move Seamerge to the Applications folder first.", bundle: .module,
        comment: "Set Up Git Integration: the app runs from a disk image or Downloads.")
    }
  }

  /// What adding Seamerge to Tower creates or adds, or what removing does there; `nil` if Tower
  /// is not installed or there is nothing to say.
  var towerText: String? {
    switch (tower, isSetUp) {
    case (.added?, true):
      String(
        localized: "Removing also takes Seamerge out of Tower.", bundle: .module,
        comment: "Set Up Git Integration: removing changes Tower too.")
    case (.notAdded(.createsList)?, _):
      String(
        localized: "Creates a list of tools and a script for Seamerge in Tower’s settings.",
        bundle: .module, comment: "Set Up Git Integration: what adding to Tower creates.")
    case (.notAdded(.addsToList)?, _):
      String(
        localized: """
          Adds Seamerge to the list of tools in Tower’s settings and creates a script for it. \
          The other tools stay.
          """, bundle: .module,
        comment: "Set Up Git Integration: what adding to Tower adds when it lists other tools.")
    case (.notAdded(.updatesEntry)?, _):
      String(
        localized: "Renews the entry and the script of Seamerge in Tower’s settings.",
        bundle: .module, comment: "Set Up Git Integration: adding to Tower renews an earlier entry."
      )
    case (.notAdded(.replacesEntry)?, _):
      String(
        localized: "Replaces the entry and the script of another copy of Seamerge in Tower.",
        bundle: .module, comment: "Set Up Git Integration: adding to Tower replaces a copy.")
    case (.unreadable?, _):
      String(
        localized: "Tower’s list of tools can’t be read, so Seamerge can’t add itself to it.",
        bundle: .module, comment: "Set Up Git Integration: Tower's list is damaged.")
    default: nil
    }
  }

  /// Whether the offer to set up Git has the box Add Seamerge to Tower.
  var offersTower: Bool {
    !isSetUp && offersAddingToTower
  }
}
