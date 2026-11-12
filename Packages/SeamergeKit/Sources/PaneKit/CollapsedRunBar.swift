import AppKit

/// The bar of a collapsed run: a quiet strip one row high across the gutter and the text, with
/// an ellipsis and the number of lines it hides.
///
/// The bar is a button, so that a click, Space or Return while it has focus, and VoiceOver expand
/// the run as they press any button. It draws its own face, darker while it is pressed, but
/// leaves focus, tracking and accessibility to `NSButton`. Like other buttons of macOS, it keeps
/// the arrow pointer and shows no hover.
final class CollapsedRunBar: NSButton {
  /// The colors and fonts of the pane.
  var theme: Theme {
    didSet { needsDisplay = true }
  }

  /// The index of the run in the pane's collapsed runs.
  let runIndex: Int

  /// The number of rows that the run hides.
  let rowCount: Int

  /// The distance from the leading edge of the bar to its symbol: where the code starts.
  var contentInset: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  /// Whether the selection of the text takes in rows that the run hides, so that copying it
  /// copies them too.
  var isWithinSelection = false

  /// The fill of the selection as the text draws it now, which changes with the focus.
  var selectionFill: () -> NSColor? = { nil }

  /// The name of the pane for VoiceOver, such as "Base", or `nil` if it has none.
  var paneName: () -> String? = { nil }

  /// Creates the bar of the run at `runIndex`, which hides `rowCount` rows.
  init(runIndex: Int, rowCount: Int, theme: Theme) {
    self.runIndex = runIndex
    self.rowCount = rowCount
    self.theme = theme
    super.init(frame: .zero)
    title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    focusRingType = .exterior
    // A button without a title would otherwise not tell VoiceOver what it is.
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityHelp(
      String(
        localized: "Shows the hidden lines.", bundle: .module,
        comment: "VoiceOver: what pressing the bar of hidden lines does."))
  }

  /// Bars are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override var isOpaque: Bool { true }

  override var isHighlighted: Bool {
    didSet {
      if isHighlighted != oldValue {
        needsDisplay = true
      }
    }
  }

  /// Names the lines the bar hides and the pane it stands in, so that the bars of the panes side
  /// by side do not all sound the same.
  override func accessibilityLabel() -> String? {
    guard let paneName = paneName() else {
      return String(
        localized: "\(rowCount) unchanged lines, collapsed", bundle: .module,
        comment: "VoiceOver: the bar that stands for unchanged lines that are hidden.")
    }
    return String(
      localized: "\(rowCount) unchanged lines in \(paneName), collapsed", bundle: .module,
      comment:
        "VoiceOver: the bar that stands for unchanged lines that are hidden in a pane, such as Base."
    )
  }

  /// The text of the bar.
  var label: String {
    String(
      localized: "\(rowCount) Unchanged Lines", bundle: .module,
      comment: "The bar that stands for unchanged lines that are hidden.")
  }

  override func draw(_ dirtyRect: NSRect) {
    Theme.backgroundColor.setFill()
    bounds.fill()
    (isHighlighted ? theme.pressedCollapsedRunFill : theme.collapsedRunFill).setFill()
    bounds.fill(using: .sourceOver)
    if isWithinSelection, let fill = selectionFill() {
      fill.setFill()
      bounds.fill(using: .sourceOver)
    }
    let color = theme.collapsedRunTextColor
    var x = contentInset
    if let symbol = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(textStyle: Theme.collapsedRunTextStyle)
          .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    {
      let size = symbol.size
      symbol.draw(
        in: CGRect(
          x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width,
          height: size.height))
      x += size.width + Theme.collapsedRunSymbolSpacing
    }
    let font = NSFont.preferredFont(forTextStyle: Theme.collapsedRunTextStyle)
    let text = NSAttributedString(
      string: label, attributes: [.font: font, .foregroundColor: color])
    let height = font.ascender - font.descender
    text.draw(at: CGPoint(x: x, y: ((bounds.height - height) / 2).rounded()))
  }

  override func drawFocusRingMask() {
    bounds.fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  /// Presses the bar for Return and Enter too, not only for Space, while it has focus.
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

/// The layer above the text and the gutter of a pane that holds the bars of collapsed runs and
/// lets every other click through to the views below.
final class CollapsedRunBarLayer: NSView {
  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }
}
