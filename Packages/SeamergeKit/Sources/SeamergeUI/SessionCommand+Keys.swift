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
    case .firstChange, .lastChange, .copyBlock:
      return nil
    }
  }

  /// The characters AppKit gives the keys of commands.
  static let upArrow = "\u{F700}"
  static let downArrow = "\u{F701}"
}
