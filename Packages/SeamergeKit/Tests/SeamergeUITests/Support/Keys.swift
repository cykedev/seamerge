import AppKit
import MergeModel

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
