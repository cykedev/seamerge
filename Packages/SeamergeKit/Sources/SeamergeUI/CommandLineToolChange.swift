import Foundation

/// A change to the link of the seamerge command, carried out by a script for `/bin/sh`.
///
/// The script gets the path of the helper as `$1` and the path of the link as `$2`, so that no
/// path ever becomes part of the text of a command that runs with an administrator's rights.
/// It checks again what lies at the link and stops with ``refusalStatus`` rather than touch a
/// file that is not a link to Seamerge. It names every program by its full path, so that no
/// `PATH` chooses which one runs.
enum CommandLineToolChange: Sendable, Equatable {
  /// Puts a link to the helper at the place of the command, where nothing or a link to a copy
  /// of Seamerge is, and creates the folder if it is missing.
  case install

  /// Removes the link at the place of the command if it is a link to a copy of Seamerge.
  case remove

  /// The exit status of the script when something other than a link to Seamerge is at the place
  /// of the command.
  static let refusalStatus: Int32 = 3

  /// The script that carries out the change.
  var script: String {
    switch self {
    case .install:
      """
      helper=$1 link=$2
      if [ -L "$link" ]; then
        case $(/usr/bin/readlink "$link") in
          *\(CommandLinePlace.helperSuffix)) ;;
          *) exit \(Self.refusalStatus) ;;
        esac
      elif [ -e "$link" ]; then
        exit \(Self.refusalStatus)
      fi
      umask 022
      /bin/mkdir -p "$(/usr/bin/dirname "$link")"
      /bin/ln -sfn "$helper" "$link"
      """
    case .remove:
      """
      link=$2
      [ -L "$link" ] || exit \(Self.refusalStatus)
      case $(/usr/bin/readlink "$link") in
        *\(CommandLinePlace.helperSuffix)) /bin/rm -f "$link" ;;
        *) exit \(Self.refusalStatus) ;;
      esac
      """
    }
  }

  /// The commands that install the link by hand in Terminal, for the user to read or copy:
  /// creating the folder if it is missing, then the link.
  static func typedCommands(for status: CommandLineToolStatus) -> [String] {
    let folder = status.link.deletingLastPathComponent().path
    let link = "sudo ln -sf \(shellQuoted(status.helper.path)) \(shellQuoted(status.link.path))"
    return status.hasLinkFolder ? [link] : ["sudo mkdir -p \(shellQuoted(folder))", link]
  }

  /// `text` as one word for a POSIX shell: unchanged if it holds no character the shell treats
  /// specially, otherwise in single quotes, as the commands of the Git setup quote it.
  static func shellQuoted(_ text: String) -> String {
    let plain = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:,@%")
    if !text.isEmpty, text.unicodeScalars.allSatisfy(plain.contains) {
      return text
    }
    return "'" + text.replacing("'", with: #"'\''"#) + "'"
  }
}
