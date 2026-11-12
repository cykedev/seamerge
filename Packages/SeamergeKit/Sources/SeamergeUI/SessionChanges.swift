import MergeModel
import PaneKit

/// The changed blocks of a session as the panes number them, and how each side shows them.
///
/// Every pane of a window has the same blocks in the same order: the blocks of the session that
/// changed, without the unchanged ones. The index of a block among them is the index the panes,
/// their overview bars and the decision column use.
struct SessionChanges {
  /// The merge or comparison.
  let session: Session

  /// The changed blocks, in the order of the session.
  let blocks: [Block]

  /// Whether the merge has a base; without one, the panes compare A with B.
  let hasBase: Bool

  /// The side that the changes of a comparison read from, the one on the left; `nil` for a
  /// merge.
  let origin: Role?

  /// Finds the changed blocks of `session`, whose changes read from `origin` if it is a
  /// comparison.
  ///
  /// Without a base, the engine counts the lines that A and B share as a change both made to an
  /// empty base; to the user they are unchanged lines, so they are left out too.
  init(session: Session, origin: Role? = nil) {
    self.session = session
    self.origin = origin
    hasBase = session.file(for: .base) != nil
    let unchangedKinds: Set<Block.Kind> = hasBase ? [.unchanged] : [.unchanged, .changedInBoth]
    blocks = session.blocks.filter { !unchangedKinds.contains($0.kind) }
  }

  /// The inputs that changed `block`, as the headers and the subtitle count changes.
  static func changers(of block: Block) -> Set<Role> {
    switch block.kind {
    case .unchanged: []
    case .changedInA: [.a]
    case .changedInB: [.b]
    case .changedInBoth, .conflict, .changed: [.a, .b]
    }
  }

  /// How many changed blocks `role` contributes to.
  func changeCount(of role: Role) -> Int {
    blocks.count { Self.changers(of: $0).contains(role) }
  }

  /// How the rows of `block` are tinted on the pane of `role`.
  ///
  /// A side is tinted where it changed the block; the base is tinted where a side changed it, in
  /// the conflict color while a conflict is open.
  func style(of role: Role, in block: Block, conflictIsOpen: Bool) -> BlockStyle {
    switch role {
    case .a: Self.changers(of: block).contains(.a) ? .tinted(.a) : .unchanged
    case .b: Self.changers(of: block).contains(.b) ? .tinted(.b) : .unchanged
    case .base: block.kind == .conflict && conflictIsOpen ? .tinted(.conflict) : .original
    }
  }

  /// The marker in the gutter of `role` at the first row of `block`: how that side changed the
  /// lines of the base, or of the other side where there is no base.
  ///
  /// In a comparison, the changes read from the origin to the other side: the side that has the
  /// lines of a block carries its marker, an insertion on the right and a removal on the left,
  /// and both sides carry the marker of lines that changed.
  func marker(of role: Role, in block: Block) -> Marker? {
    guard role != .base, Self.changers(of: block).contains(role) else { return nil }
    let own = block.lines(in: role).count
    let other = block.lines(in: role == .a ? .b : .a).count
    if let origin {
      guard own > 0 else { return nil }
      if other > 0 { return .changed }
      return role == origin ? .removed : .added
    }
    let reference = hasBase ? block.base.count : other
    switch (reference, own) {
    case (0, _): return .added
    case (_, 0): return .removed
    default: return .changed
    }
  }

  /// The pane that carries the mark of a conflict: the base, or B where there is no base or
  /// its pane is hidden.
  func conflictMarkRole(baseIsShown: Bool) -> Role {
    hasBase && baseIsShown ? .base : .b
  }
}
