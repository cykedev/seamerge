import AppKit

/// The table of the ignore rules in Settings, which takes a few keys of its own besides those
/// of every table: Space switches the selected rules on or off, Return edits the name of the
/// selected rule, and Delete removes the selected rules of the user.
@MainActor
final class IgnoreRuleTableView: NSTableView {
  /// What the keys of the table ask for.
  enum KeyCommand {
    /// Switches the selected rules on or off.
    case toggle

    /// Edits the name of the selected rule.
    case edit

    /// Removes the selected rules.
    case remove
  }

  /// Carries out a key command, or tells that it has no effect, in which case the key does
  /// what it does in every table.
  var perform: ((KeyCommand) -> Bool)?

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.numericPad, .function])
    guard modifiers.isEmpty, let command = Self.command(for: event.charactersIgnoringModifiers),
      perform?(command) == true
    else {
      super.keyDown(with: event)
      return
    }
  }

  /// The command of the key that types `characters`, if it has one.
  private static func command(for characters: String?) -> KeyCommand? {
    switch characters {
    case " ": .toggle
    case "\r", "\u{3}": .edit
    // Delete, and Forward Delete as the function key NSDeleteFunctionKey types it.
    case "\u{7f}", "\u{F728}": .remove
    default: nil
    }
  }
}
