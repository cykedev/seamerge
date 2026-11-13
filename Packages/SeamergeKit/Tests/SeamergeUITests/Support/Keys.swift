import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// A key equivalent with its modifier keys, which tests compare.
struct Keys: Equatable, CustomStringConvertible {
  var key: String
  var modifiers: NSEvent.ModifierFlags

  init(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
    self.key = key
    self.modifiers = modifiers
  }

  /// The key equivalent of `command` in a window of `kind`, if it has one.
  static func of(_ command: SessionCommand, in kind: Session.Kind) -> Keys? {
    command.keyEquivalent(in: kind).map { Keys($0.key, $0.modifiers) }
  }

  var description: String {
    "\(key.unicodeScalars.map { String($0.value, radix: 16) }) \(modifiers.rawValue)"
  }
}

/// Sends a key press of `characters` with `modifiers` to the window of `controller`, as the
/// keyboard does.
@MainActor
func press(
  _ characters: String, modifiers: NSEvent.ModifierFlags = [],
  in controller: SessionWindowController
) throws {
  let window = try #require(controller.window)
  window.sendEvent(try event(characters, modifiers: modifiers, in: window))
}

/// A key down of `characters` with `modifiers` for `window`.
@MainActor
func event(
  _ characters: String, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow
) throws -> NSEvent {
  try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
}
