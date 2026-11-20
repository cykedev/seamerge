import Foundation

/// The words and the button of the sheet Install the seamerge Command, as they follow from what
/// lies at the place of the command.
extension CommandLineToolStatus {
  /// What the sheet offers.
  package enum Offer: Equatable {
    /// Installing the link, where nothing or a file of someone else is.
    case install

    /// Pointing the link of another copy to this one.
    case update

    /// Removing the link of this copy.
    case remove

    /// Nothing: Homebrew installed the command, and the sheet only says so.
    case none
  }

  /// What the sheet offers.
  package var offer: Offer {
    switch entry {
    case .none, .otherFile: .install
    case .otherCopy: .update
    case .thisCopy: .remove
    case .homebrew: .none
    }
  }

  /// The change the button of the offer makes, or `nil` if the sheet offers nothing.
  package var change: CommandLineToolChange? {
    switch offer {
    case .install, .update: .install
    case .remove: .remove
    case .none: nil
    }
  }

  /// Whether the button of the offer works: a file of someone else is never replaced, and a copy
  /// in a temporary place never linked.
  package var canConfirm: Bool {
    switch offer {
    case .remove: true
    case .install, .update:
      if case .otherFile = entry { false } else { problem == nil }
    case .none: false
    }
  }

  /// Whether the sheet has Show Command: wherever it offers to make the link.
  package var showsCommands: Bool {
    switch entry {
    case .none, .otherCopy: true
    case .thisCopy, .homebrew, .otherFile: false
    }
  }

  /// The title of the sheet: the offer, or the state once the command is installed.
  package var sheetTitle: String {
    switch offer {
    case .install:
      String(
        localized: "Install the seamerge Command", bundle: .module,
        comment: "Install the seamerge Command: the title of the offer.")
    case .update:
      String(
        localized: "Update the seamerge Command", bundle: .module,
        comment: "Install the seamerge Command: the title when the link names a moved copy.")
    case .remove, .none:
      String(
        localized: "The seamerge Command Is Installed", bundle: .module,
        comment: "Install the seamerge Command: the title once the command is installed.")
    }
  }

  /// What the change does, or who installed the command.
  package var sheetMessage: String {
    let link = link.path
    switch offer {
    case .install:
      return String(
        localized: """
          Adds a link at \(link) so that you can compare files in Terminal, for example \
          seamerge old.txt new.txt. macOS asks for an administrator’s name and password.
          """, bundle: .module,
        comment: "Install the seamerge Command: what installing does; the path of the link.")
    case .update:
      return String(
        localized: """
          The seamerge command points to a copy of Seamerge that has moved. Updating points it \
          to this copy. macOS asks for an administrator’s name and password.
          """, bundle: .module,
        comment: "Install the seamerge Command: the link names another copy of the app.")
    case .remove:
      return String(
        localized: """
          You can compare files in Terminal, for example seamerge old.txt new.txt. Removing \
          deletes the link at \(link). macOS asks for an administrator’s name and password.
          """, bundle: .module,
        comment: "Install the seamerge Command: what removing does; the path of the link.")
    case .none:
      return String(
        localized: "Homebrew installed the seamerge command.", bundle: .module,
        comment: "Install the seamerge Command: Homebrew made the link.")
    }
  }

  /// What lies in the way of the link, or `nil` if nothing does.
  package var otherFileText: String? {
    guard case .otherFile(let destination) = entry else { return nil }
    guard let destination else {
      return String(
        localized: "Another file is at \(link.path). Seamerge doesn’t replace it.",
        bundle: .module,
        comment: "Install the seamerge Command: a file of someone else is where the link goes.")
    }
    return String(
      localized: "\(link.path) is a link to \(destination). Seamerge doesn’t replace it.",
      bundle: .module,
      comment: "Install the seamerge Command: a link of someone else is where the link goes.")
  }

  /// Why this copy cannot be linked, or `nil` if it can or the sheet does not offer it.
  package var problemText: String? {
    guard offer == .install || offer == .update else { return nil }
    return problem?.text
  }

  /// What the dialog of macOS that asks for the password says: who asks, and what for.
  package var dialogPrompt: String {
    let folder = link.deletingLastPathComponent().path
    return switch offer {
    case .install, .none:
      String(
        localized: "Seamerge wants to install the seamerge command in \(folder).",
        bundle: .module,
        comment: "The dialog of macOS that asks for an administrator's password; a folder.")
    case .update:
      String(
        localized: "Seamerge wants to update the seamerge command in \(folder).",
        bundle: .module,
        comment: "The dialog of macOS that asks for an administrator's password; a folder.")
    case .remove:
      String(
        localized: "Seamerge wants to remove the seamerge command from \(folder).",
        bundle: .module,
        comment: "The dialog of macOS that asks for an administrator's password; a folder.")
    }
  }

  /// The sentence below the commands: the folder that the shell must search.
  package var pathNote: String {
    let folder = link.deletingLastPathComponent().path
    return String(
      localized: "If Terminal doesn’t find seamerge, add \(folder) to the PATH of your shell.",
      bundle: .module,
      comment: "Install the seamerge Command: below the commands; the folder of the link.")
  }

  /// What VoiceOver says once the sheet has made `change`.
  package static func announcement(after change: CommandLineToolChange) -> String {
    switch change {
    case .install:
      String(
        localized: "The seamerge command is installed.", bundle: .module,
        comment: "VoiceOver: the link of the command was made or updated.")
    case .remove:
      String(
        localized: "The seamerge command is removed.", bundle: .module,
        comment: "VoiceOver: the link of the command was removed.")
    }
  }
}

extension AppLocation.Problem {
  /// Why this copy cannot be linked, in the words of the Git setup.
  var text: String {
    switch self {
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
}
