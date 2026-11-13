extension ResultDocument {
  /// The plan that switches the toggle of `role` in a block on or off.
  ///
  /// Switching on appends the toggle's text after the texts of the toggles already on; switching
  /// off takes it out. A toggle without text, such as one that follows a deletion, is exclusive:
  /// switching it on switches the others off, and switching another on switches it off. Either
  /// way the segment then holds the texts of the toggles that are on, in the order they were
  /// switched on, whatever it held before.
  ///
  /// Switching off the last toggle reopens a conflict. In any other block the last toggle stays
  /// on; if the segment was edited, its sources replace the edited text.
  ///
  /// - Precondition: `block` belongs to the session, and `role` takes part in it.
  public func planToggling(_ role: Role, in block: Block) -> EditPlan {
    let index = index(of: block)
    let segment = segments[index]
    let toggles = toggles(in: block)
    let toggle = SegmentTexts.toggle(for: role, among: toggles)
    var switchedOn = SegmentTexts.toggles(switchedOnBy: segment.sources, among: toggles)
    if let position = switchedOn.firstIndex(of: toggle) {
      switchedOn.remove(at: position)
      if switchedOn.isEmpty {
        if block.kind == .conflict {
          return planRewriting([index: Segment(state: .open)])
        }
        guard segment.state == .edited else { return .empty }
        switchedOn = [toggle]
      }
    } else {
      switchedOn = Self.switchingOn(toggle, after: switchedOn)
    }
    return planRewriting([index: Segment(state: .chosen, sources: switchedOn.flatMap(\.roles))])
  }

  /// The plan that takes the texts of `roles` in a block, in that order, as if their toggles were
  /// switched on one after the other and all others were off.
  ///
  /// One role takes only that source; no roles take nothing and leave the segment empty, which
  /// also resolves a conflict.
  ///
  /// - Precondition: `block` belongs to the session, and `roles` take part in it.
  public func planChoosing(_ roles: [Role], in block: Block) -> EditPlan {
    let index = index(of: block)
    return planRewriting([index: chosenSegment(roles, toggles: toggles(in: block))])
  }

  /// The plan that resolves every open conflict with the texts of `roles`, as
  /// ``planChoosing(_:in:)`` resolves one.
  ///
  /// - Precondition: `roles` take part in the session.
  public func planResolvingOpenConflicts(with roles: [Role]) -> EditPlan {
    var decisions: [Int: Segment] = [:]
    for index in segments.indices where segments[index].state == .open {
      decisions[index] = chosenSegment(roles, toggles: texts.toggles(in: session.blocks[index]))
    }
    return planRewriting(decisions)
  }

  /// Turns a block's segment into text to edit by hand, with the cursor at its start.
  ///
  /// The preview of an open conflict becomes text, A then B; a removal note gives way to the
  /// nothing it stands for. An empty segment gets an empty line, which belongs to the block.
  /// Either way the segment becomes edited. Any other segment is already text to edit and stays
  /// as it is; only the cursor moves.
  ///
  /// - Precondition: `block` belongs to the session.
  public func planResolvingByHand(_ block: Block) -> ManualResolution {
    let index = index(of: block)
    let range = self.range(of: block)
    let start = range.lowerBound
    var after = segments[index]
    var replacements: [TextReplacement] = []
    if after.state == .open {
      let sides = texts.sideTexts(of: session.blocks[index])
      if sides != texts.previewText(for: session.blocks[index]) {
        replacements = [TextReplacement(range: range, text: sides)]
        after.length = sides.utf16.count
      }
    }
    if after.length == 0 {
      replacements = [TextReplacement(range: start..<start, text: texts.lineEnding)]
      after.length = texts.lineEnding.utf16.count
    } else if after.state != .open {
      return ManualResolution(plan: .empty, cursorPosition: start)
    }
    after.state = .edited
    let plan = EditPlan(
      replacements: replacements,
      tableChanges: [.segment(index: index, before: segments[index], after: after)],
      isTyping: false)
    return ManualResolution(plan: plan, cursorPosition: start)
  }

  /// The segment that takes the texts of `roles`, in that order.
  private func chosenSegment(_ roles: [Role], toggles: [Toggle]) -> Segment {
    var switchedOn: [Toggle] = []
    for role in roles {
      let toggle = SegmentTexts.toggle(for: role, among: toggles)
      if !switchedOn.contains(toggle) {
        switchedOn = Self.switchingOn(toggle, after: switchedOn)
      }
    }
    return Segment(state: .chosen, sources: switchedOn.flatMap(\.roles))
  }

  /// The toggles that are on after switching on `toggle`, which is off, after `switchedOn`.
  private static func switchingOn(_ toggle: Toggle, after switchedOn: [Toggle]) -> [Toggle] {
    toggle.isExclusive ? [toggle] : switchedOn.filter { !$0.isExclusive } + [toggle]
  }
}
