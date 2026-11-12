/// What resolving a block by hand does: the plan that turns its segment into text to edit, and
/// where the cursor goes.
public struct ManualResolution: Sendable {
  /// The plan to carry out; empty if the segment is already text to edit.
  public let plan: EditPlan

  /// The position for the cursor once the plan is carried out: the start of the block's segment,
  /// in UTF-16 code units.
  public let cursorPosition: Int
}
