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
      .ignoreWhitespaceChanges, .ignoreAllWhitespace, .toggleInvisibles, .copyBlock:
      return nil
    case .swapSides: return ("s", [.option, .command])
    case .toggleBase: return ("b", [.option, .command])
    case .toggleResultMaximized: return ("r", [.option, .command])
    case .toggleScrollSynchronization: return ("y", [.option, .command])
    case .toggleCollapsedLines: return ("l", [.shift, .command])
    case .zoomIn: return ("+", [.command])
    case .zoomOut: return ("-", [.command])
    case .actualSize: return ("0", [.command])
    case .goToLine: return ("l", [.command])
    case .openInEditor: return ("o", [.option, .command])
    case .nextPane: return (Self.tab, [.control])
    case .previousPane: return (Self.tab, [.shift, .control])
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
