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
        needsDisplay = true
      }
    }
  }

  /// The outline of the control, which its fills and its focus ring follow.
  var outline: NSBezierPath {
    NSBezierPath(
      roundedRect: bounds, xRadius: Theme.toggleCornerRadius, yRadius: Theme.toggleCornerRadius)
  }

  /// Fills the outline quietly while the control is pressed.
  func drawPressedFill() {
    guard isHighlighted else { return }
    theme.pressedDecisionControlFill.setFill()
    outline.fill()
  }

  override func drawFocusRingMask() {
    outline.fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  /// Presses the control for Return and Enter too, not only for Space, while it has focus.
  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers {
    case "\r", "\u{3}":
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
}

/// A toggle of a block: the names of its inputs, filled in the color of its side while it is on,
/// the names alone while it is off.
///
/// For VoiceOver it is a toggle button, on or off, named after its inputs, with the sentence of
/// what it does as help.
final class DecisionToggleButton: DecisionControl {
  /// The toggle that the button shows.
  var toggle: DecisionToggle {
    didSet {
      toolTip = toggle.help
      needsDisplay = true
    }
  }

  /// The index of the toggle among the block's toggles.
  let index: Int

  init(block: Int, index: Int, toggle: DecisionToggle, theme: Theme) {
    self.toggle = toggle
    self.index = index
    super.init(block: block, theme: theme)
    toolTip = toggle.help
  }

  /// Toggle buttons are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The width that the button takes for `toggle`, at least the smallest target of a click.
  static func width(of toggle: DecisionToggle) -> CGFloat {
    let label = NSAttributedString(string: label(of: toggle), attributes: [.font: font])
    var width = label.size().width + 2 * Theme.toggleLabelPadding
    if toggle.isDeletion, let symbol = trashSymbol(color: .labelColor) {
      width += Theme.toggleSymbolSpacing + symbol.size.width
    }
    return max(width.rounded(.up), Theme.decisionControlSize)
  }

  override func draw(_ dirtyRect: NSRect) {
    let color = theme.decisionColor(for: toggle.roles)
    if toggle.isOn {
      color.setFill()
      outline.fill()
    }
    drawPressedFill()
    // Pressed, a toggle that is off shows its label in the color of text, which stays legible on
    // the pressed fill where the color of a side would not.
    let labelColor =
      toggle.isOn ? theme.filledLabelColor : isHighlighted ? Theme.textColor : color
    let label = NSAttributedString(
      string: Self.label(of: toggle), attributes: [.font: Self.font, .foregroundColor: labelColor])
    let symbol = toggle.isDeletion ? Self.trashSymbol(color: labelColor) : nil
    let labelSize = label.size()
    let contentWidth =
      labelSize.width + (symbol.map { Theme.toggleSymbolSpacing + $0.size.width } ?? 0)
    var x = ((bounds.width - contentWidth) / 2).rounded()
    Self.draw(label, at: x, centeringCapitalsOn: bounds.midY)
    x += labelSize.width + Theme.toggleSymbolSpacing
    if let symbol {
      Self.draw(symbol, centeredOn: bounds.midY, at: x)
    }
  }

  /// Draws `label` with its leading edge at `x` and its capitals centered on `middle`, so that it
  /// looks centered: a line of text leaves more room above the capitals, for accents, than below
  /// them.
  static func draw(
    _ label: NSAttributedString, at x: CGFloat, centeringCapitalsOn middle: CGFloat
  ) {
    let font = label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Self.font
    // Without the line fragment option, the origin of the rectangle is the baseline.
    label.draw(
      with: CGRect(
        x: x, y: middle + font.capHeight / 2, width: label.size().width,
        height: font.ascender - font.descender),
      options: [])
  }

  /// Draws `symbol` with its leading edge at `x` and its middle on `middle`, the optical middle
  /// of the capitals beside it.
  ///
  /// A symbol image keeps room around its glyph so that the glyph's ink is centered in it; its
  /// alignment rectangle, which is only as high as capitals, would place a tall symbol such as
  /// the trash can half a point too high.
  static func draw(_ symbol: NSImage, centeredOn middle: CGFloat, at x: CGFloat) {
    let size = symbol.size
    symbol.draw(
      in: CGRect(x: x, y: middle - size.height / 2, width: size.width, height: size.height))
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

  override func accessibilityLabel() -> String? {
    let names = Self.spokenNames(of: toggle.roles)
    guard toggle.isDeletion else { return names }
    return String(
      localized: "\(names), deletion", bundle: .module,
      comment: "VoiceOver: a toggle that follows the inputs named in removing lines, such as A.")
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

  /// The label of `toggle`: the names of its inputs, joined by a middle dot.
  static func label(of toggle: DecisionToggle) -> String {
    toggle.roles.map(name(of:)).joined(separator: " · ")
  }

  /// The name of an input on a toggle and in a state sign.
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

  /// The font of the labels.
  static var font: NSFont {
    .systemFont(
      ofSize: NSFont.preferredFont(forTextStyle: Theme.toggleTextStyle).pointSize,
      weight: .semibold)
  }

  /// The trash can after the label of a toggle that follows a deletion, in `color`.
  ///
  /// It takes the weight of the label at the small scale, a point smaller than the label: at the
  /// label's own size the can stands a point and a half above the capitals beside it and looks
  /// heavier than they do.
  private static func trashSymbol(color: NSColor) -> NSImage? {
    NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(
          pointSize: font.pointSize - Theme.toggleSymbolSizeReduction, weight: .semibold,
          scale: .small
        )
        .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
  }
}

/// The arrow beside the toggles of a block that differs from how it was loaded, which resets it.
final class ResetBlockButton: DecisionControl {
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
          NSImage.SymbolConfiguration(textStyle: Theme.toggleTextStyle)
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

/// The toggles and the reset arrow of one block, side by side, which VoiceOver finds as a group
/// named after the block's state and line, at the place of the block.
final class DecisionControlGroup: NSView {
  /// The controls, in the order they stand.
  let controls: [DecisionControl]

  init(controls: [DecisionControl]) {
    self.controls = controls
    super.init(frame: .zero)
    for control in controls {
      addSubview(control)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  /// Groups are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  /// Passes clicks between the controls on to the column.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  /// Passes scrolling on to the pane, which scrolls its text.
  override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }
}
