import AppKit

/// The narrow column at the right edge of the result pane that shows how each block came by its
/// text and offers the toggles that decide it.
///
/// The column is nearly empty: at the first row of each block that has a sign, a small sign of its
/// state. At the current block, and at the block under the pointer once the pointer has rested
/// there for a moment, the sign gives way to the block's toggles and, if the block can be reset,
/// an arrow that resets it. The column shows what it is given and changes nothing on its own: it
/// tells its delegate what the user pressed.
///
/// Install the column on a pane with ``PaneView/decisionColumn``; the pane places it beside its
/// text and keeps it in step with its rows, its scroll position and its current block. Its width
/// follows from the widest row of controls a block can have, so that it never changes.
public final class DecisionColumnView: NSView {
  /// The colors and fonts of the column.
  public var theme = Theme() {
    didSet {
      removeAllControls()
      update()
    }
  }

  /// What the column shows for each block, by the index of the block in the pane's content.
  ///
  /// A block without an entry has neither a sign nor toggles.
  public var decisions: [Int: BlockDecision] = [:] {
    didSet { update() }
  }

  /// Learns what the user presses; the column does not retain it.
  public weak var delegate: (any DecisionColumnDelegate)?

  /// The pane that the column stands in.
  weak var host: (any DecisionColumnHost)?

  /// The block under the pointer whose toggles show, if any.
  private(set) var hoveredBlock: Int?

  /// The block that the pointer rests on, whose toggles show once it has rested long enough.
  private var restingBlock: Int?

  /// Shows the toggles of the block that the pointer rests on, once it has rested long enough.
  private(set) var hoverTimer: Timer?

  /// The group of the toggles and the reset arrow of each block that shows them.
  private var groupsByBlock: [Int: DecisionControlGroup] = [:]

  /// The element that VoiceOver finds for the sign of each block, kept while the sign is in view
  /// so that its cursor can stay on it.
  private var signElements: [Int: NSAccessibilityElement] = [:]

  /// Creates an empty column.
  public init() {
    super.init(frame: .zero)
    clipsToBounds = true
  }

  /// Decision columns are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  isolated deinit {
    hoverTimer?.invalidate()
  }

  public override var isFlipped: Bool { true }

  /// The width of the column: room for the widest row of controls, rounded to the layout grid.
  ///
  /// The widest rows are three toggles, a toggle that follows a deletion beside two inputs that
  /// share one, and both sides sharing one beside the base, each with the reset arrow.
  static var width: CGFloat {
    let rows: [[DecisionToggle]] = [
      [[.a], [.base], [.b]].map { DecisionToggle(roles: $0, isOn: true, help: "") },
      [
        DecisionToggle(roles: [.a], isOn: true, isDeletion: true, help: ""),
        DecisionToggle(roles: [.base, .b], isOn: true, help: ""),
      ],
      [[.a, .b], [.base]].map { DecisionToggle(roles: $0, isOn: true, help: "") },
    ]
    let widest =
      rows.map { toggles in
        toggles.map(DecisionToggleButton.width(of:)).reduce(0, +)
          + CGFloat(toggles.count) * Theme.decisionControlSpacing + Theme.decisionControlSize
      }.max() ?? 0
    let width = widest + 2 * Theme.decisionColumnInset
    return (width / Theme.layoutGrid).rounded(.up) * Theme.layoutGrid
  }

  /// Shows the controls of the current block and of the block under the pointer where their
  /// blocks now are, and draws the signs again: after the pane scrolled, changed its rows or its
  /// current block.
  func update() {
    showControls()
    needsDisplay = true
  }

  /// The blocks that show their controls instead of their sign.
  private var blocksWithControls: [Int] {
    var blocks: [Int] = []
    for block in [host?.currentBlock, hoveredBlock].compactMap(\.self)
    where decisions[block] != nil && !blocks.contains(block) {
      blocks.append(block)
    }
    return blocks
  }

  private func showControls() {
    let blocks = blocksWithControls
    for block in groupsByBlock.keys where !blocks.contains(block) {
      removeControls(of: block)
    }
    for block in blocks {
      guard let host, let decision = decisions[block], let center = host.signCenter(ofBlock: block)
      else {
        removeControls(of: block)
        continue
      }
      let group = group(of: block, showing: decision)
      var x: CGFloat = 0
      for control in group.controls {
        let width =
          (control as? DecisionToggleButton).map { DecisionToggleButton.width(of: $0.toggle) }
          ?? Theme.decisionControlSize
        control.frame = CGRect(x: x, y: 0, width: width, height: Theme.decisionControlSize)
        x += width + Theme.decisionControlSpacing
      }
      group.frame = CGRect(
        x: Theme.decisionColumnInset, y: (center - Theme.decisionControlSize / 2).rounded(),
        width: max(x - Theme.decisionControlSpacing, 0), height: Theme.decisionControlSize)
      group.setAccessibilityLabel(
        [
          StateSign(state: decision.state, theme: theme).accessibilityLabel,
          host.placeDescription(ofBlock: block),
        ].compactMap(\.self).joined(separator: ", "))
    }
  }

  /// The group of the controls of `block` for `decision`: the one it has if its controls fit,
  /// made anew otherwise, with the keyboard focus kept on the control at the same place.
  private func group(of block: Int, showing decision: BlockDecision) -> DecisionControlGroup {
    if let group = groupsByBlock[block] {
      let toggles = group.controls.compactMap { $0 as? DecisionToggleButton }
      let hasReset = group.controls.contains { $0 is ResetBlockButton }
      if toggles.count == decision.toggles.count && hasReset == decision.canReset {
        for (button, toggle) in zip(toggles, decision.toggles) {
          button.toggle = toggle
        }
        return group
      }
    }
    let focused = groupsByBlock[block]?.controls.firstIndex { window?.firstResponder === $0 }
    removeControls(of: block)
    var controls: [DecisionControl] = decision.toggles.enumerated().map { index, toggle in
      let button = DecisionToggleButton(block: block, index: index, toggle: toggle, theme: theme)
      button.target = self
      button.action = #selector(toggleWasPressed(_:))
      return button
    }
    if decision.canReset {
      let reset = ResetBlockButton(block: block, theme: theme)
      reset.target = self
      reset.action = #selector(resetWasPressed(_:))
      controls.append(reset)
    }
    let group = DecisionControlGroup(controls: controls)
    addSubview(group)
    groupsByBlock[block] = group
    if let focused {
      window?.makeFirstResponder(controls[min(focused, controls.count - 1)])
    }
    return group
  }

  private func removeControls(of block: Int) {
    guard let group = groupsByBlock.removeValue(forKey: block) else { return }
    let hadFocus = group.controls.contains { window?.firstResponder === $0 }
    group.removeFromSuperview()
    if hadFocus {
      window?.makeFirstResponder(nil)
    }
  }

  private func removeAllControls() {
    for block in Array(groupsByBlock.keys) {
      removeControls(of: block)
    }
  }

  @objc private func toggleWasPressed(_ sender: DecisionToggleButton) {
    delegate?.decisionColumn(self, didSwitchToggle: sender.index, ofBlock: sender.block)
  }

  @objc private func resetWasPressed(_ sender: ResetBlockButton) {
    delegate?.decisionColumn(self, didAskToResetBlock: sender.block)
  }

  public override func draw(_ dirtyRect: NSRect) {
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    let withControls = blocksWithControls
    for (block, decision) in decisions where !withControls.contains(block) {
      guard let center = host?.signCenter(ofBlock: block),
        center + Theme.stateSignHeight >= dirtyRect.minY,
        center - Theme.stateSignHeight <= dirtyRect.maxY
      else { continue }
      StateSign(state: decision.state, theme: theme)
        .draw(at: CGPoint(x: Theme.decisionColumnInset, y: center))
    }
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }

  public override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  public override func mouseExited(with event: NSEvent) {
    pointerLeft()
  }

  /// Follows the pointer to `point`: the toggles of the block below it show once it rests there,
  /// those of a block it left go at once.
  func pointerMoved(to point: CGPoint) {
    let block = host?.block(atY: point.y).flatMap { decisions[$0] == nil ? nil : $0 }
    guard block != hoveredBlock else {
      cancelHover()
      return
    }
    if hoveredBlock != nil {
      hoveredBlock = nil
      update()
    }
    cancelHover()
    guard let block else { return }
    restingBlock = block
    let timer = Timer(timeInterval: Theme.toggleHoverDelay, repeats: false) { [weak self] _ in
      // Timers of the main run loop fire on the main thread.
      MainActor.assumeIsolated { self?.pointerRested() }
    }
    RunLoop.main.add(timer, forMode: .common)
    hoverTimer = timer
  }

  /// Hides the toggles of the block that the pointer was over.
  func pointerLeft() {
    cancelHover()
    if hoveredBlock != nil {
      hoveredBlock = nil
      update()
    }
  }

  private func pointerRested() {
    hoverTimer = nil
    hoveredBlock = restingBlock
    restingBlock = nil
    update()
  }

  private func cancelHover() {
    hoverTimer?.invalidate()
    hoverTimer = nil
    restingBlock = nil
  }

  /// Passes scrolling on to the pane, which scrolls its text.
  public override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  public override func isAccessibilityElement() -> Bool {
    true
  }

  public override func accessibilityRole() -> NSAccessibility.Role? {
    .group
  }

  public override func accessibilityLabel() -> String? {
    String(
      localized: "Decisions", bundle: .module,
      comment: "VoiceOver: the column beside the result that shows how each block was decided.")
  }

  /// The sign of each block in view, named with its state and its line, and in place of the sign
  /// of a block that shows its controls, the group of those, all from top to bottom.
  public override func accessibilityChildren() -> [Any]? {
    guard let host else { return [] }
    let withControls = blocksWithControls
    var children: [(center: CGFloat, element: Any)] = []
    var shownSigns: Set<Int> = []
    for (block, decision) in decisions where !withControls.contains(block) {
      let sign = StateSign(state: decision.state, theme: theme)
      guard let label = sign.accessibilityLabel, let center = host.signCenter(ofBlock: block),
        bounds.minY...bounds.maxY ~= center
      else { continue }
      let element = signElements[block] ?? NSAccessibilityElement()
      element.setAccessibilityRole(.image)
      element.setAccessibilityLabel(label)
      element.setAccessibilityValue(host.placeDescription(ofBlock: block))
      element.setAccessibilityParent(self)
      element.setAccessibilityFrameInParentSpace(
        CGRect(
          x: Theme.decisionColumnInset, y: center - Theme.stateSignHeight / 2,
          width: max(sign.width, Theme.stateSignHeight), height: Theme.stateSignHeight))
      signElements[block] = element
      shownSigns.insert(block)
      children.append((center, element))
    }
    signElements = signElements.filter { shownSigns.contains($0.key) }
    for group in groupsByBlock.values {
      children.append((group.frame.midY, group))
    }
    return children.sorted { $0.center < $1.center }.map(\.element)
  }
}

/// What the decision column needs to know of the pane it stands in.
@MainActor
protocol DecisionColumnHost: AnyObject {
  /// The index of the current block, if any.
  var currentBlock: Int? { get }

  /// The vertical middle of the place of `block`'s sign and controls in the column: its first
  /// row, or for a block without rows the boundary where it lies; `nil` while that is behind the
  /// bar of a collapsed run.
  func signCenter(ofBlock block: Int) -> CGFloat?

  /// The block whose rows lie at `y` of the column, if any.
  func block(atY y: CGFloat) -> Int?

  /// Where `block` is, in words, such as "Line 12".
  func placeDescription(ofBlock block: Int) -> String
}
