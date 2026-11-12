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

  /// Whether the sign of a block and its controls replace each other at once, as Reduce Motion
  /// asks, rather than cross-fading.
  public var reducesMotion = false

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

  /// What fades out or in at the place of a block while its sign and its controls cross-fade:
  /// the sign, and the controls that it takes the place of again.
  private var fades: [Int: Fade] = [:]

  /// The layer above the signs that holds what fades, which neither clicks nor VoiceOver reach.
  private let fadeLayer = DecisionFadeLayer()

  /// Creates an empty column.
  public init() {
    super.init(frame: .zero)
    clipsToBounds = true
    // The cross-fades run on layers.
    wantsLayer = true
    addSubview(fadeLayer)
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
    cachedSignPlaces = nil
    showControls()
    updateToolTips()
    needsDisplay = true
  }

  /// Gives each sign in view an area of its own for a help tag, whose text
  /// ``view(_:stringForToolTip:point:userData:)`` finds; the controls have their own tags.
  private func updateToolTips() {
    removeAllToolTips()
    for (block, center) in shownSigns {
      guard let decision = decisions[block] else { continue }
      addToolTip(signRect(at: center, for: decision), owner: self, userData: nil)
    }
  }

  /// The blocks whose signs are in view, with the middles of their places.
  private var shownSigns: [(block: Int, center: CGFloat)] {
    let withControls = blocksWithControls
    return signPlaces.centers.filter { block, center in
      !withControls.contains(block) && bounds.minY...bounds.maxY ~= center
    }.map { ($0.key, $0.value) }
  }

  /// The area of the sign of `decision` centered at `center`: as wide as the sign and as high as
  /// the room of a click.
  private func signRect(at center: CGFloat, for decision: BlockDecision) -> CGRect {
    let sign = StateSign(state: decision.state, theme: theme)
    return CGRect(
      x: Theme.decisionColumnInset, y: center - Theme.decisionControlSize / 2,
      width: max(sign.width, Theme.decisionControlSize), height: Theme.decisionControlSize)
  }

  /// Where the signs stand, until the column updates.
  private var cachedSignPlaces: SignPlaces?

  /// Where the signs stand: at their blocks, moved apart where two would come closer than the
  /// room of a click, and within the rows of the text.
  ///
  /// The signs of every block take part, so that a chain of close signs comes out the same
  /// wherever the pane is scrolled.
  private var signPlaces: SignPlaces {
    if let cachedSignPlaces { return cachedSignPlaces }
    guard let host else { return SignPlaces(anchors: [], spacing: 0, within: 0...0) }
    let anchors: [SignPlaces.Anchor] = decisions.keys.sorted().compactMap { block in
      host.signCenter(ofBlock: block).map {
        SignPlaces.Anchor(block: block, center: $0, liesBetweenRows: host.liesBetweenRows(block))
      }
    }
    let places = SignPlaces(
      anchors: anchors, spacing: Theme.decisionControlSize, within: host.rowsExtent)
    cachedSignPlaces = places
    return places
  }

  /// The vertical middle of the sign and the controls of `block`, if it has a sign.
  private func signCenter(ofBlock block: Int) -> CGFloat? {
    signPlaces.centers[block]
  }

  /// The block whose sign or controls lie at `y`, or else whose rows do, if it has a decision.
  private func block(atY y: CGFloat) -> Int? {
    if let block = signPlaces.block(atY: y, spacing: Theme.decisionControlSize) {
      return block
    }
    return host?.block(atY: y).flatMap { decisions[$0] == nil ? nil : $0 }
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
    fadeLayer.frame = bounds
    let blocks = blocksWithControls
    for block in groupsByBlock.keys where !blocks.contains(block) {
      fadeOutControls(of: block)
    }
    for block in blocks {
      guard let host, let decision = decisions[block], let center = signCenter(ofBlock: block)
      else {
        removeControls(of: block)
        continue
      }
      let isNew = groupsByBlock[block] == nil
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
      let sign = StateSign(state: decision.state, theme: theme)
      group.setAccessibilityLabel(
        [sign.accessibilityLabel, host.placeDescription(ofBlock: block)].compactMap(\.self)
          .joined(separator: ", "))
      // The controls take the place of the sign, whose meaning stays with them.
      group.setAccessibilityHelp(sign.help)
      group.toolTip = sign.help
      if isNew {
        fadeInControls(group, of: block, replacing: decision.state)
      }
    }
    placeFades()
  }

  /// Fades `group` in at the place of `block` while the sign of `state` there fades out.
  private func fadeInControls(
    _ group: DecisionControlGroup, of block: Int, replacing state: BlockDecision.State
  ) {
    // Controls that were still fading out give way at once.
    fades[block]?.controls?.removeFromSuperview()
    fades[block]?.controls = nil
    guard !reducesMotion, window != nil else {
      endFade(of: block)
      return
    }
    let sign = fades[block]?.sign ?? StateSignView(state: state, theme: theme)
    fadeLayer.addSubview(sign)
    fades[block, default: Fade()].sign = sign
    group.alphaValue = 0
    runFade {
      sign.animator().alphaValue = 0
      group.animator().alphaValue = 1
    } completion: { [weak self] in
      guard let self, fades[block]?.sign === sign, sign.alphaValue == 0 else { return }
      endFade(of: block)
    }
  }

  /// Takes the controls of `block` away and fades them out while its sign fades in.
  private func fadeOutControls(of block: Int) {
    guard let group = groupsByBlock[block], let decision = decisions[block], !reducesMotion,
      window != nil
    else {
      removeControls(of: block)
      endFade(of: block)
      return
    }
    removeControls(of: block)
    let frame = convert(group.frame, to: fadeLayer)
    fadeLayer.addSubview(group)
    group.frame = frame
    let sign = fades[block]?.sign ?? StateSignView(state: decision.state, theme: theme)
    if sign.superview == nil {
      sign.alphaValue = 0
      fadeLayer.addSubview(sign)
    }
    fades[block]?.controls?.removeFromSuperview()
    fades[block] = Fade(sign: sign, controls: group)
    runFade {
      sign.animator().alphaValue = 1
      group.animator().alphaValue = 0
    } completion: { [weak self] in
      guard let self, fades[block]?.controls === group else { return }
      endFade(of: block)
    }
  }

  /// Ends the cross-fade at the place of `block`: what faded goes, and the column draws the
  /// sign again if the block shows no controls.
  private func endFade(of block: Int) {
    guard let fade = fades.removeValue(forKey: block) else { return }
    fade.sign?.removeFromSuperview()
    fade.controls?.removeFromSuperview()
    needsDisplay = true
  }

  /// Runs `changes` as a cross-fade and then `completion`.
  private func runFade(
    _ changes: @escaping () -> Void, completion: @escaping @MainActor () -> Void
  ) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Theme.decisionFadeDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      changes()
    } completionHandler: {
      MainActor.assumeIsolated { completion() }
    }
  }

  /// Keeps what fades at the places of its blocks, which move as the pane scrolls.
  private func placeFades() {
    for (block, fade) in fades {
      guard let center = signCenter(ofBlock: block) else {
        endFade(of: block)
        continue
      }
      fade.sign?.frame = CGRect(
        x: Theme.decisionColumnInset, y: (center - Theme.decisionControlSize / 2).rounded(),
        width: bounds.width - Theme.decisionColumnInset, height: Theme.decisionControlSize)
      if let controls = fade.controls {
        controls.frame.origin.y = (center - Theme.decisionControlSize / 2).rounded()
      }
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
    for block in Array(fades.keys) {
      endFade(of: block)
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
    // A sign that fades draws in a view of its own.
    for (block, decision) in decisions where !withControls.contains(block) && fades[block] == nil {
      guard let center = signCenter(ofBlock: block),
        center + Theme.stateSignHeight >= dirtyRect.minY,
        center - Theme.stateSignHeight <= dirtyRect.maxY
      else { continue }
      StateSign(state: decision.state, theme: theme)
        .draw(at: CGPoint(x: Theme.decisionColumnInset, y: center))
    }
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    // Only the area of the pointer: the help tags of the signs have areas of their own.
    if let pointerArea {
      removeTrackingArea(pointerArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    pointerArea = area
  }

  /// The area that follows the pointer over the column.
  private var pointerArea: NSTrackingArea?

  /// Tells the delegate which block the click is beside; a click on a control reaches the
  /// control instead.
  public override func mouseDown(with event: NSEvent) {
    guard let block = block(atY: convert(event.locationInWindow, from: nil).y) else { return }
    delegate?.decisionColumn(self, didClickBlock: block)
  }

  public override func mouseMoved(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  /// Follows the pointer from where it enters, which may already be the place where it rests.
  public override func mouseEntered(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  public override func mouseExited(with event: NSEvent) {
    pointerLeft()
  }

  /// Follows the pointer to `point`: the toggles of the block below it show once it rests there,
  /// those of a block it left go at once.
  func pointerMoved(to point: CGPoint) {
    let block = block(atY: point.y)
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
      guard let label = sign.accessibilityLabel, let center = signCenter(ofBlock: block),
        bounds.minY...bounds.maxY ~= center
      else { continue }
      let element = signElements[block] ?? NSAccessibilityElement()
      element.setAccessibilityRole(.image)
      element.setAccessibilityLabel(label)
      element.setAccessibilityHelp(sign.help)
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

  /// The vertical middle of the place that `block` asks for its sign and controls in the
  /// column: its first row, or for a block without rows the boundary where it lies; `nil` while
  /// that is behind the bar of a collapsed run.
  ///
  /// The column moves signs apart that would come too close; see ``SignPlaces``.
  func signCenter(ofBlock block: Int) -> CGFloat?

  /// Whether `block` has no rows and lies on the boundary between two.
  func liesBetweenRows(_ block: Int) -> Bool

  /// Where the rows of the text lie in the column, from the top of the first to the bottom of
  /// the last, as the pane is scrolled.
  var rowsExtent: ClosedRange<CGFloat> { get }

  /// The block whose rows lie at `y` of the column, if any.
  func block(atY y: CGFloat) -> Int?

  /// Where `block` is, in words, such as "Line 12".
  func placeDescription(ofBlock block: Int) -> String
}

extension DecisionColumnView: NSViewToolTipOwner {
  /// What the sign at `point` means.
  public func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    let hit = shownSigns.first { block, center in
      decisions[block].map { signRect(at: center, for: $0).contains(point) } == true
    }
    guard let hit, let decision = decisions[hit.block] else { return "" }
    return StateSign(state: decision.state, theme: theme).help ?? ""
  }
}

/// What fades at the place of one block of the decision column.
@MainActor
private struct Fade {
  /// The block's sign, fading out as its controls come, or in as they go.
  var sign: StateSignView?
  /// The block's controls, fading out as its sign comes back.
  var controls: DecisionControlGroup?
}

/// The layer of the decision column that holds what fades: it lets clicks through to the column
/// and is hidden from VoiceOver, which finds the sign or the controls that stay.
private final class DecisionFadeLayer: NSView {
  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func isAccessibilityElement() -> Bool {
    false
  }

  override func accessibilityChildren() -> [Any]? {
    []
  }
}

/// The sign of one block in a view of its own, while it fades.
private final class StateSignView: NSView {
  private let sign: StateSign

  init(state: BlockDecision.State, theme: Theme) {
    sign = StateSign(state: state, theme: theme)
    super.init(frame: .zero)
  }

  /// Sign views are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    sign.draw(at: CGPoint(x: 0, y: bounds.midY))
  }
}
