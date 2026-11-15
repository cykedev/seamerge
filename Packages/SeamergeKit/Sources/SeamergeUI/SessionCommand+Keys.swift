import AppKit
import MergeModel

extension SessionCommand {
  /// The key equivalent of the command in a window of `kind`, with its modifier keys, or `nil`
  /// for a command without one.
  ///
  /// Option-Command-Down Arrow and Up Arrow follow the count of the toolbar: in a merge they jump
  /// between open conflicts, in a comparison of two files, which has none, between changes.
  public func keyEquivalent(
    in kind: Session.Kind
  ) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
    let jumps: NSEvent.ModifierFlags = [.option, .command]
    let changeJumps: NSEvent.ModifierFlags = kind == .merge ? [.shift, .option, .command] : jumps
    switch self {
    case .nextConflict: return kind == .merge ? (Self.downArrow, jumps) : nil
    case .previousConflict: return kind == .merge ? (Self.upArrow, jumps) : nil
    case .nextChange: return (Self.downArrow, changeJumps)
    case .previousChange: return (Self.upArrow, changeJumps)
    case .firstChange, .lastChange, .compareExactly, .ignoreLineEndings,
      .ignoreWhitespaceChanges, .ignoreAllWhitespace, .toggleSyntaxHighlighting, .toggleInvisibles,
      .toggleIgnoredChanges, .copyBlock:
      return nil
    case .swapSides: return ("s", [.option, .command])
    case .skipRemainingFiles: return kind == .diff ? (".", [.command]) : nil
    case .leaveUnresolved: return kind == .merge ? (".", [.command]) : nil
    case .save: return ("s", [.command])
    case .saveAndClose: return ("\r", [.command])
    case .saveAs, .changeFiles: return nil
    case .toggleBase: return ("b", [.option, .command])
    case .toggleResultMaximized: return ("r", [.option, .command])
    case .toggleScrollSynchronization: return ("y", [.option, .command])
    case .toggleLineWrapping: return ("l", [.option, .command])
    case .toggleLineAlignment: return ("a", [.option, .command])
    case .showAllLines: return ("l", [.shift, .command])
    case .collapseUnchangedLines: return ("l", [.option, .shift, .command])
    case .toggleFooter: return ("/", [.command])
    case .zoomIn: return ("+", [.command])
    case .zoomOut: return ("-", [.command])
    case .actualSize: return ("0", [.command])
    case .goToLine: return ("l", [.command])
    case .openInEditor: return ("o", [.option, .command])
    case .nextFile: return kind == .diff ? (Self.rightArrow, jumps) : nil
    case .filterFiles: return kind == .diff ? ("f", [.shift, .command]) : nil
    case .toggleIdenticalFiles: return nil
    case .previousFile: return kind == .diff ? (Self.leftArrow, jumps) : nil
    case .nextPane: return (Self.tab, [.control])
    case .previousPane: return (Self.tab, [.shift, .control])
    case .useA: return ("1", [.command])
    case .useBase: return ("2", [.command])
    case .useB: return ("3", [.command])
    case .useAThenB: return ("4", [.command])
    case .useBThenA: return ("5", [.command])
    case .useNone: return ("6", [.command])
    case .toggleSourceA: return ("1", [.option, .command])
    case .toggleSourceBase: return ("2", [.option, .command])
    case .toggleSourceB: return ("3", [.option, .command])
    case .resetChange: return (Self.backspace, [.option, .command])
    case .resetAllDecisions: return (Self.backspace, [.shift, .option, .command])
    case .resolveManually, .reopenAllConflicts, .resolveAllWithA, .resolveAllWithB: return nil
    }
  }

  /// The keys without Command or Control that carry out the command in block mode, while the
  /// focus is in a pane above the result.
  var blockModeKeys: [Keystroke] {
    switch self {
    case .nextConflict: [Keystroke("n")]
    case .previousConflict: [Keystroke("n", .shift)]
    case .nextChange: [Keystroke(Self.downArrow)]
    case .previousChange: [Keystroke(Self.upArrow)]
    case .firstChange: [Keystroke(Self.home)]
    case .lastChange: [Keystroke(Self.end)]
    case .nextPane: [Keystroke(Self.tab)]
    case .previousPane: [Keystroke(Self.tab, .shift), Keystroke(Self.backTab, .shift)]
    case .useA: [Keystroke("1"), Keystroke(Self.leftArrow)]
    case .useBase: [Keystroke("2")]
    case .useB: [Keystroke("3"), Keystroke(Self.rightArrow)]
    case .useAThenB: [Keystroke("4")]
    case .useBThenA: [Keystroke("5")]
    case .useNone: [Keystroke("6")]
    case .toggleSourceA: [Keystroke("1", .option)]
    case .toggleSourceBase: [Keystroke("2", .option)]
    case .toggleSourceB: [Keystroke("3", .option)]
    case .resolveManually: [Keystroke("\r"), Keystroke("\u{3}")]
    default: []
    }
  }

  /// The command that `keystroke` carries out in block mode, if any.
  init?(blockModeKey keystroke: Keystroke) {
    guard let command = Self.allCases.first(where: { $0.blockModeKeys.contains(keystroke) })
    else { return nil }
    self = command
  }

  /// The characters AppKit gives the keys of commands.
  static let upArrow = "\u{F700}"
  static let downArrow = "\u{F701}"
  static let leftArrow = "\u{F702}"
  static let rightArrow = "\u{F703}"
  static let backspace = "\u{8}"
  static let home = "\u{F729}"
  static let end = "\u{F72B}"
  static let tab = "\t"
  static let backTab = "\u{19}"
}

/// A key with the modifier keys held with it, as block mode reads it: the character of the key
/// without Shift, in lower case.
struct Keystroke: Equatable {
  let key: String
  let modifiers: NSEvent.ModifierFlags

  init(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) {
    self.key = key.lowercased()
    self.modifiers = modifiers
  }
}
