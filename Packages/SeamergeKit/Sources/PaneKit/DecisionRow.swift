import AppKit

/// The row of one block in the decision column: the bar of toggles with a segment for each
/// input in its slot, red while the block is an open conflict, and in the place beside it the
/// arrow that resets the block.
///
/// VoiceOver finds the row as a group named after the block's line, with its state as value,
/// and one toggle button for each toggle and the arrow. The row passes clicks beside its
/// controls on to the column.
final class DecisionRow: NSView {
  /// The index of the block in the pane's content.
  let block: Int

  /// The colors of the column, and with them the height of its rows.
  var theme: Theme {
    didSet {
      for control in controls {
        control.theme = theme
      }
      placeControls()
      needsDisplay = true
    }
  }

  /// Where the parts of the row stand.
  private var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: theme)
  }

  /// The segment of each input of the block, by its slot.
  private var segmentsBySlot: [DecisionColumnLayout.Slot: DecisionToggleButton] = [:]

  /// The arrow that resets the block, while it can be reset.
  private var resetButton: ResetBlockButton?

  /// Whether the block is an open conflict, whose bar the row draws red.
  private var isOpenConflict = false

  /// What the segments tell when they are pressed.
  private let toggleAction: (target: AnyObject, action: Selector)

  /// What the arrow tells when it is pressed.
  private let resetAction: (target: AnyObject, action: Selector)

  init(
    block: Int, theme: Theme, toggleAction: (target: AnyObject, action: Selector),
    resetAction: (target: AnyObject, action: Selector)
  ) {
    self.block = block
    self.theme = theme
    self.toggleAction = toggleAction
    self.resetAction = resetAction
    super.init(frame: .zero)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  /// Rows are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  /// The segments and the arrow, in the order they stand.
  var controls: [DecisionControl] {
    DecisionColumnLayout.Slot.allCases.compactMap { segmentsBySlot[$0] }
      + [resetButton].compactMap(\.self)
  }

  /// Shows `decision` for the block, which stands at `place`, such as "Line 12".
  ///
  /// The segments that the block keeps stay, and with them the keyboard focus.
  func show(_ decision: BlockDecision, place: String) {
    let focused = controls.first { window?.firstResponder === $0 }
    var shown: [DecisionColumnLayout.Slot: DecisionToggleButton] = [:]
    for (index, toggle) in decision.toggles.enumerated() {
      let face = Self.face(of: toggle, in: decision.state)
      var toggleSegments: [DecisionToggleButton] = []
      for slot in DecisionColumnLayout.Slot.allCases {
        guard let role = toggle.roles.first(where: { DecisionColumnLayout.slot(of: $0) == slot })
        else { continue }
        let isPrimary = toggleSegments.isEmpty
        let segment: DecisionToggleButton
        if let existing = segmentsBySlot[slot], existing.index == index {
          segment = existing
          segment.toggle = toggle
          segment.face = face
          segment.isPrimary = isPrimary
        } else {
          segment = DecisionToggleButton(
            block: block, role: role, index: index, toggle: toggle, face: face,
            isPrimary: isPrimary, theme: theme)
          segment.target = toggleAction.target
          segment.action = toggleAction.action
          addSubview(segment)
        }
        shown[slot] = segment
        toggleSegments.append(segment)
      }
      for segment in toggleSegments {
        segment.partners = toggleSegments.filter { $0 !== segment }
      }
    }
    for (slot, segment) in segmentsBySlot where shown[slot] !== segment {
      segment.removeFromSuperview()
    }
    segmentsBySlot = shown
    isOpenConflict = decision.state == .open
    showResetButton(decision.canReset && !isOpenConflict)
    placeControls()
    if let focused, focused.superview !== self {
      window?.makeFirstResponder(controls.first { $0.acceptsFirstResponder })
    }
    setAccessibilityLabel(place)
    setAccessibilityValue(decision.state.spokenName)
    setAccessibilityHelp(decision.state.help)
    toolTip = decision.state.help
    needsDisplay = true
  }

  /// How a segment of `toggle` looks for a block in `state`: tinted where the merge took its
  /// inputs, filled where the user chose them or edited the block since.
  private static func face(
    of toggle: DecisionToggle, in state: BlockDecision.State
  ) -> DecisionToggleButton.Face {
    guard toggle.isOn else { return .off }
    switch state {
    case .unchanged, .automatic: return .automatic
    case .chosen, .edited: return .chosen
    case .open: return .off
    }
  }

  private func showResetButton(_ isShown: Bool) {
    guard isShown != (resetButton != nil) else { return }
    if let resetButton {
      resetButton.removeFromSuperview()
      self.resetButton = nil
      return
    }
    let button = ResetBlockButton(block: block, theme: theme)
    button.target = resetAction.target
    button.action = resetAction.action
    addSubview(button)
    resetButton = button
  }

  /// Puts each control into its slot.
  private func placeControls() {
    let layout = layout
    for (slot, segment) in segmentsBySlot {
      segment.frame = layout.frame(of: slot)
      segment.barRect = layout.barRect
    }
    resetButton?.frame = layout.frame(of: .place)
    resetButton?.symbolSize = layout.letterSize
  }

  override func draw(_ dirtyRect: NSRect) {
    let segments = DecisionColumnLayout.Slot.allCases.compactMap { slot in
      segmentsBySlot[slot].map {
        DecisionBar.Segment(
          slot: slot, role: $0.role, face: $0.face, removesLines: $0.toggle.isDeletion)
      }
    }
    DecisionBar(segments: segments, isOpenConflict: isOpenConflict, theme: theme)
      .draw(at: window?.backingScaleFactor ?? 1)
  }

  /// Passes clicks beside the controls on to the column.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  /// Passes scrolling on to the pane, which scrolls its text.
  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  /// The toggle buttons, one for each toggle, and the arrow.
  override func accessibilityChildren() -> [Any]? {
    controls.filter { $0.isAccessibilityElement() }
  }
}
