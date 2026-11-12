import MergeModel

/// Which panes a session window shows and where: the inputs side by side from left to right,
/// and below them the result, which only a merge has.
///
/// A merge shows A, Base and B, as far as they take part, above its result. A comparison of two
/// files shows the older file on the left and the newer one on the right, and nothing below;
/// Swap Sides puts them the other way round. The changes read from left to right either way,
/// so that a block the left side lacks is an insertion.
struct PaneArrangement: Equatable {
  /// The inputs from left to right.
  private(set) var sourceRoles: [Role]

  /// Whether the result stands below the inputs.
  let showsResult: Bool

  /// The arrangement a new window has for `session`.
  init(session: Session) {
    switch session.kind {
    case .merge:
      sourceRoles = [.a, .base, .b].filter(session.roles.contains)
      showsResult = true
    case .diff:
      sourceRoles = [.a, .b]
      showsResult = false
    }
  }

  /// Whether the two sides can change places, as in a comparison of two files.
  var canSwapSides: Bool {
    !showsResult
  }

  /// Puts the left side on the right and the right side on the left.
  ///
  /// - Precondition: The sides can change places.
  mutating func swapSides() {
    precondition(canSwapSides, "Only the sides of a comparison change places")
    sourceRoles.reverse()
  }

  /// The side the changes of a comparison read from, the one on the left; `nil` for a merge,
  /// whose sides change the base.
  var origin: Role? {
    showsResult ? nil : sourceRoles.first
  }

  /// The input on the left.
  var leadingRole: Role {
    sourceRoles[0]
  }

  /// The input on the right.
  var trailingRole: Role {
    sourceRoles[sourceRoles.count - 1]
  }
}
