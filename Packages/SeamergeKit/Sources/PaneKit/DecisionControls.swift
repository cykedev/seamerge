import AppKit

/// A control of the decision column: a button that draws its own face, quietly filled while it is
/// pressed, and leaves focus, tracking and accessibility to `NSButton`.
class DecisionControl: NSButton {
  /// The colors of the column.
  var theme: Theme {
    didSet { needsDisplay = true }
  }

  /// The index of the block in the pane's content that the control acts on.
  let block: Int

  init(block: Int, theme: Theme) {
    self.block = block
    self.theme = theme
    super.init(frame: .zero)
    title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    focusRingType = .exterior
    setAccessibilityElement(true)
  }

  /// Controls are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override var isHighlighted: Bool {
    didSet {
      if isHighlighted != oldValue {
        highlightDidChange()
      }
    }
  }

  /// Draws the control again after it was pressed or let go.
  func highlightDidChange() {
    needsDisplay = true
  }

  /// Whether the control shows that it is pressed.
  var looksPressed: Bool {
    isHighlighted
  }

  /// The outline of the control, which its fills and its focus ring follow.
  var outline: NSBezierPath {
    NSBezierPath(
      roundedRect: bounds, xRadius: Theme.resetCornerRadius, yRadius: Theme.resetCornerRadius)
  }

  /// Fills the outline quietly while the control is pressed.
  func drawPressedFill() {
    guard looksPressed else { return }
    theme.pressedDecisionControlFill.setFill()
    outline.fill()
  }

  override func drawFocusRingMask() {
    outline.fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  /// Gives the pane of the column the focus, as a click anywhere in a pane does, then tracks the
  /// click as a button does.
  override func mouseDown(with event: NSEvent) {
    enclosingColumn?.focusPane()
    super.mouseDown(with: event)
  }

  /// Takes the keyboard focus only under Keyboard Navigation, which the column passes on, as a
  /// control of the system does.
  override var acceptsFirstResponder: Bool {
    enclosingColumn?.navigatesWithKeyboard == true && !refusesFirstResponder
  }

  override var canBecomeKeyView: Bool {
    acceptsFirstResponder
  }

  /// Moves the focus to the control beside it for the side arrow keys, as within a segmented
  /// control; Space presses the control, as for any button.
  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) }) {
    case NSLeftArrowFunctionKey:
      (superview as? DecisionRow)?.moveFocus(from: self, by: -1)
    case NSRightArrowFunctionKey:
      (superview as? DecisionRow)?.moveFocus(from: self, by: 1)
    case 0x20:
      performClick(self)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    performClick(self)
    return true
  }

  /// Passes scrolling on to the pane, which scrolls its text.
  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  /// The decision column that the control stands in.
  var enclosingColumn: DecisionColumnView? {
    sequence(first: superview, next: { $0?.superview }).lazy.compactMap {
      $0 as? DecisionColumnView
    }.first
  }
}

/// The segment of one input in the bar of toggles of a block, which takes the clicks, the
/// keyboard focus and VoiceOver for it; the row draws the bar.
///
/// Inputs with the same text share a toggle; each has a segment of its own, and the segments of
/// one toggle switch and press together. The first of them stands for the toggle for the
/// keyboard and VoiceOver: a toggle button, on or off, named after the inputs, with the sentence
/// of what it does as help. The others take clicks only.
final class DecisionToggleButton: DecisionControl {
  /// How a segment looks.
  enum Face {
    /// The input is not taken: its sign alone, quiet.
    case off
    /// The merge took the input: lightly tinted in the color of its side, its sign in that
    /// color.
    case automatic
    /// The user chose the input: filled in the color of its side.
    case chosen
  }

  /// The input that the segment stands for.
  let role: ColorRole

  /// The index of the segment's toggle among the block's toggles.
  let index: Int

  /// The toggle that the segment belongs to.
  var toggle: DecisionToggle {
    didSet { toolTip = toggle.help }
  }

  /// How the segment looks.
  var face: Face

  /// Whether the segment stands for its toggle for the keyboard and VoiceOver.
  var isPrimary: Bool {
    didSet {
      setAccessibilityElement(isPrimary)
      refusesFirstResponder = !isPrimary
    }
  }

  /// The other segments of the same toggle, which are pressed with this one.
  var partners: [DecisionToggleButton] = []

  /// Whether a partner is being pressed.
  private var isPressedWithPartner = false {
    didSet { needsDisplay = true }
  }

  init(
    block: Int, role: ColorRole, index: Int, toggle: DecisionToggle, face: Face, isPrimary: Bool,
    theme: Theme
  ) {
    self.role = role
    self.index = index
    self.toggle = toggle
    self.face = face
    self.isPrimary = isPrimary
    super.init(block: block, theme: theme)
    toolTip = toggle.help
    setAccessibilityElement(isPrimary)
    refusesFirstResponder = !isPrimary
  }

  /// Toggle buttons are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var looksPressed: Bool {
    isHighlighted || isPressedWithPartner
  }

  override func highlightDidChange() {
    super.highlightDidChange()
    for partner in partners {
      partner.isPressedWithPartner = isHighlighted
    }
  }

  /// The bar of toggles in the row, of which the segment shows its part.
  var barRect = CGRect.zero {
    didSet { needsDisplay = true }
  }

  /// The bar of toggles in the segment's own coordinates, of which the segment shows its part.
  override var outline: NSBezierPath {
    let bar = barRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    let radius = bar.height / 2
    return NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius)
  }

  /// Draws nothing but the quiet fill while the segment is pressed: the row draws the bar.
  override func draw(_ dirtyRect: NSRect) {
    clippedToSegment(drawPressedFill)
  }

  override func drawFocusRingMask() {
    clippedToSegment { outline.fill() }
  }

  /// Runs `drawing` with the drawing clipped to the segment's part of the bar.
  private func clippedToSegment(_ drawing: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    .checkBox
  }

  override func accessibilitySubrole() -> NSAccessibility.Subrole? {
    .toggle
  }

  override func accessibilityValue() -> Any? {
    NSNumber(value: toggle.isOn)
  }

  /// The names of the toggle's inputs in the order their segments stand, such as "A and Base",
  /// and what taking them does where they removed the lines.
  override func accessibilityLabel() -> String? {
    let order: [ColorRole] = [.a, .base, .b]
    let names = Self.spokenNames(of: order.filter(toggle.roles.contains))
    guard toggle.isDeletion else { return names }
    return String(
      localized: "\(names), removes these lines", bundle: .module,
      comment: "VoiceOver: a toggle that follows the inputs named in removing the lines, such as A."
    )
  }

  override func accessibilityHelp() -> String? {
    toggle.help
  }

  /// The names of `roles` as VoiceOver says them, such as "Base and B".
  ///
  /// The interface is English in any locale, so the names are not joined by the locale's list
  /// format.
  static func spokenNames(of roles: [ColorRole]) -> String {
    let names = roles.map(name(of:))
    guard let last = names.last, names.count > 1 else { return names.first ?? "" }
    let first = names.dropLast().joined(separator: ", ")
    return String(
      localized: "\(first) and \(last)", bundle: .module,
      comment: "VoiceOver: the inputs that share a toggle, such as Base and B.")
  }

  /// The name of an input as VoiceOver says it, and as the letters of the bar show A and B.
  static func name(of role: ColorRole) -> String {
    switch role {
    case .a:
      String(localized: "A", bundle: .module, comment: "The name of the incoming side on a toggle.")
    case .base:
      String(
        localized: "Base", bundle: .module, comment: "The name of the common ancestor on a toggle.")
    case .b, .conflict:
      String(localized: "B", bundle: .module, comment: "The name of the own side on a toggle.")
    }
  }
}

/// The arrow beside the toggles of a block that differs from how it was loaded, which resets it.
final class ResetBlockButton: DecisionControl {
  /// The size of the arrow, that of the letters of the bar beside it.
  var symbolSize = Theme.smallestFontSize {
    didSet { needsDisplay = true }
  }

  override init(block: Int, theme: Theme) {
    super.init(block: block, theme: theme)
    toolTip = Self.help
    setAccessibilityRole(.button)
    setAccessibilityLabel(
      String(
        localized: "Reset Block", bundle: .module,
        comment: "VoiceOver: the arrow that resets a block to how it was loaded."))
    setAccessibilityHelp(Self.help)
  }

  /// Reset buttons are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    drawPressedFill()
    guard
      let symbol = NSImage(
        systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Theme.secondaryMarkColor])))
    else { return }
    let size = symbol.size
    symbol.draw(
      in: CGRect(
        x: ((bounds.width - size.width) / 2).rounded(),
        y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height))
  }

  /// What the button does, as its help tag.
  private static var help: String {
    String(
      localized: "Return the block to how it was after loading", bundle: .module,
      comment: "Help tag of the arrow that resets a block.")
  }
}
