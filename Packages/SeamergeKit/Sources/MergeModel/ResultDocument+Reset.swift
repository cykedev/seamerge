extension ResultDocument {
  /// Whether a block's segment differs from how it was after loading.
  ///
  /// - Precondition: `block` belongs to the session.
  public func canReset(_ block: Block) -> Bool {
    differsFromInitial(index(of: block))
  }

  /// Whether any conflict differs from how it was after loading.
  public var canResetConflicts: Bool {
    segments.indices.contains { session.blocks[$0].kind == .conflict && differsFromInitial($0) }
  }

  /// Whether any block differs from how it was after loading.
  public var canResetAll: Bool {
    segments.indices.contains(where: differsFromInitial)
  }

  /// The number of blocks whose segment holds text edited by hand, which resetting every block
  /// would discard.
  public var editedBlockCount: Int {
    segments.count { $0.state == .edited }
  }

  /// The plan that returns a block to how it was after loading, discarding any text edited by
  /// hand in it.
  ///
  /// A conflict is open again and shows its preview; any other block takes the source it was
  /// loaded with.
  ///
  /// - Precondition: `block` belongs to the session.
  public func planResetting(_ block: Block) -> EditPlan {
    let index = index(of: block)
    return planRewriting([index: initialSegments[index]])
  }

  /// The plan that opens every conflict again and leaves the other blocks as they are.
  public func planResettingConflicts() -> EditPlan {
    var decisions: [Int: Segment] = [:]
    for index in segments.indices where session.blocks[index].kind == .conflict {
      decisions[index] = initialSegments[index]
    }
    return planRewriting(decisions)
  }

  /// The plan that returns every block to how it was after loading, so that the text is the
  /// initial text again.
  public func planResettingAll() -> EditPlan {
    planRewriting(Dictionary(uniqueKeysWithValues: initialSegments.enumerated().map { ($0, $1) }))
  }

  /// Whether the segment at `index` differs in its decision from how it was after loading.
  private func differsFromInitial(_ index: Int) -> Bool {
    !segments[index].hasSameDecision(as: initialSegments[index])
  }
}
