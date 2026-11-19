import Foundation

/// What the decision column shows for one block of the result: its bar of toggles, which also
/// shows its state, and beside it the arrow that resets it.
package struct BlockDecision: Sendable, Hashable {
  /// How the block came by its text, which its toggles show.
  package enum State: Sendable, Hashable {
    /// The block has the text it was loaded with; the toggles that are on show tinted.
    case unchanged
    /// The merge took the sources given; their toggles show tinted.
    case automatic([ColorRole])
    /// The user chose the sources given, in the order chosen; their toggles show filled, and
    /// none if the block takes nothing.
    case chosen([ColorRole])
    /// The user edited the block by hand; the toggles of the sources it had show filled.
    case edited
    /// The block is a conflict that awaits a decision; every toggle is off, and the bar is red.
    case open
  }

  /// How the block came by its text.
  package var state: State

  /// The toggles of the block, one to three, in the order they stand.
  package var toggles: [DecisionToggle]

  /// Whether the block differs from how it was loaded, so that an arrow beside its toggles
  /// offers to reset it.
  package var canReset: Bool

  /// Creates what the column shows for a block.
  ///
  /// - Precondition: There are one to three toggles.
  package init(state: State, toggles: [DecisionToggle], canReset: Bool = false) {
    precondition((1...3).contains(toggles.count), "A block has one to three toggles")
    self.state = state
    self.toggles = toggles
    self.canReset = canReset
  }
}

extension BlockDecision.State {
  /// What VoiceOver says for the state of a block, or `nil` for an unchanged block.
  @MainActor package var spokenName: String? {
    func names(_ roles: [ColorRole]) -> String {
      roles.map(DecisionToggleButton.name(of:)).joined(separator: ", ")
    }
    switch self {
    case .unchanged:
      return nil
    case .automatic(let roles):
      return String(
        localized: "Taken automatically: \(names(roles))", bundle: .module,
        comment: "VoiceOver: a block whose sources the merge took, such as A.")
    case .chosen(let roles) where roles.isEmpty:
      return String(
        localized: "Nothing taken", bundle: .module,
        comment: "VoiceOver: a block that takes no lines from any input.")
    case .chosen(let roles):
      return String(
        localized: "Chosen: \(names(roles))", bundle: .module,
        comment: "VoiceOver: a block whose sources the user chose, in order, such as B, A.")
    case .edited:
      return String(
        localized: "Edited by hand", bundle: .module,
        comment: "VoiceOver: a block whose text the user typed or changed.")
    case .open:
      return String(
        localized: "Open conflict", bundle: .module,
        comment: "VoiceOver: a conflict that still needs a decision.")
    }
  }

  /// What the state means, as the help tag of the block's row and the help that VoiceOver
  /// reads, or `nil` for an unchanged block.
  @MainActor var help: String? {
    switch self {
    case .unchanged:
      return nil
    case .automatic(let roles):
      let names = DecisionToggleButton.spokenNames(of: roles)
      return String(
        localized: "Takes the lines of \(names), as the merge decided", bundle: .module,
        comment: "Help tag of a block whose sources the merge took, such as A and B.")
    case .chosen(let roles) where roles.isEmpty:
      return String(
        localized: "Takes no lines, as you chose", bundle: .module,
        comment: "Help tag of a block that takes no lines from any input.")
    case .chosen(let roles):
      let names = DecisionToggleButton.spokenNames(of: roles)
      return String(
        localized: "Takes the lines of \(names), in the order you chose", bundle: .module,
        comment: "Help tag of a block whose sources the user chose, such as B and A.")
    case .edited:
      return String(
        localized: "Holds lines that you typed or changed", bundle: .module,
        comment: "Help tag of a block whose text the user typed or changed.")
    case .open:
      return MarkHelp.conflict(.open)
    }
  }
}

/// A switch that adds the text of one or more inputs to a block of the result, or takes it out.
package struct DecisionToggle: Sendable, Hashable {
  /// The inputs that share the toggle because they have the same text in the block, in the order
  /// base, A, B; each shows in a segment of its own, and the segments switch together.
  package var roles: [ColorRole]

  /// Whether the toggle is switched on.
  package var isOn: Bool

  /// Whether switching the toggle on follows its inputs in removing the block's lines; its
  /// segments show a trash can in place of their letters.
  package var isDeletion: Bool

  /// What switching the toggle does, in a whole sentence with the real names, such as "Take the
  /// version of feature/login."; shown as its help tag and read by VoiceOver.
  package var help: String

  /// Creates a toggle.
  ///
  /// - Precondition: `roles` names at least one of A, base and B, and not the conflict; a toggle
  ///   that follows a deletion does not include the base, whose lines a deletion removes.
  package init(roles: [ColorRole], isOn: Bool, isDeletion: Bool = false, help: String) {
    precondition(
      !roles.isEmpty && !roles.contains(.conflict), "A toggle stands for one or more inputs")
    precondition(!(isDeletion && roles.contains(.base)), "The base never follows a deletion")
    self.roles = roles
    self.isOn = isOn
    self.isDeletion = isDeletion
    self.help = help
  }
}
