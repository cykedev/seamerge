/// What the decision column shows for one block of the result: the sign of its state and, while
/// the block is current or under the pointer, its toggles.
public struct BlockDecision: Sendable, Hashable {
  /// How the block came by its text, which the column shows as a small sign at its first row.
  public enum State: Sendable, Hashable {
    /// The block has the text it was loaded with and needs no sign.
    case unchanged
    /// The merge took the sources given, which show as outlined letters.
    case automatic([ColorRole])
    /// The user chose the sources given, in the order chosen, which show as filled letters; a
    /// trash can if the block takes nothing.
    case chosen([ColorRole])
    /// The user edited the block by hand; shown as a pencil.
    case edited
    /// The block is a conflict that awaits a decision; shown as a warning sign.
    case open
  }

  /// How the block came by its text.
  public var state: State

  /// The toggles of the block, one to three, in the order they stand.
  public var toggles: [DecisionToggle]

  /// Whether the block differs from how it was loaded, so that an arrow beside its toggles
  /// offers to reset it.
  public var canReset: Bool

  /// Creates what the column shows for a block.
  ///
  /// - Precondition: There are one to three toggles.
  public init(state: State, toggles: [DecisionToggle], canReset: Bool = false) {
    precondition((1...3).contains(toggles.count), "A block has one to three toggles")
    self.state = state
    self.toggles = toggles
    self.canReset = canReset
  }
}

extension BlockDecision.State {
  /// What VoiceOver says for the state, as the sign of the decision column says it, or `nil`
  /// for an unchanged block, which has no sign.
  @MainActor public var spokenName: String? {
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
}

/// A switch that adds the text of one or more inputs to a block of the result, or takes it out.
public struct DecisionToggle: Sendable, Hashable {
  /// The inputs that share the toggle because they have the same text in the block, in the order
  /// base, A, B; its label names them, such as `Base · B`.
  public var roles: [ColorRole]

  /// Whether the toggle is switched on.
  public var isOn: Bool

  /// Whether switching the toggle on follows its inputs in removing the block's lines; it shows a
  /// trash can after its label.
  public var isDeletion: Bool

  /// What switching the toggle does, in a whole sentence with the real names, such as "Take the
  /// version of feature/login."; shown as its help tag and read by VoiceOver.
  public var help: String

  /// Creates a toggle.
  ///
  /// - Precondition: `roles` names at least one of A, base and B, and not the conflict.
  public init(roles: [ColorRole], isOn: Bool, isDeletion: Bool = false, help: String) {
    precondition(
      !roles.isEmpty && !roles.contains(.conflict), "A toggle stands for one or more inputs")
    self.roles = roles
    self.isOn = isOn
    self.isDeletion = isDeletion
    self.help = help
  }
}
