import AppKit

/// The bar of a collapsed run: a quiet strip one row high across the gutter and the text, with
/// an ellipsis and the number of lines it hides.
///
/// The bar is a button, so that a click, Space or Return while it has focus, and VoiceOver expand
/// the run as they press any button. It draws its own face, darker while it is pressed, but
/// leaves focus, tracking and accessibility to `NSButton`. Like other buttons of macOS, it keeps
/// the arrow pointer and shows no hover.
///
/// The bar of a run that stands for lines the pane does not have looks the same but names them
/// as lines not in the patch; it is text rather than a button, since there is nothing to expand.
final class CollapsedRunBar: NSButton {
  /// The colors and fonts of the pane.
  var theme: Theme {
    didSet {
      ellipsis = nil
      needsDisplay = true
    }
  }

  /// The ellipsis in the color of the text, made when first drawn; the color is resolved as it
  /// draws, so one image serves every appearance.
  ///
  /// AppKit draws a view again each time it moves, so a bar draws on every step of scrolling;
  /// made anew each time, the symbol would be looked up and rendered anew as well.
  private var ellipsis: NSImage?

  /// The index of the run in the pane's collapsed runs.
  let runIndex: Int

  /// The number of lines that the run hides or stands for.
  let lineCount: Int

  /// Whether pressing the bar expands its run, which a run of lines the pane does not have never
  /// does.
  let expands: Bool

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

  /// Gives the pane of the bar the focus, as a click anywhere in a pane does.
  var focusPane: () -> Void = {}

  /// Creates the bar of the run at `runIndex`, which hides `lineCount` rows, or which stands for
  /// `lineCount` lines the pane does not have unless it `expands`.
  init(runIndex: Int, lineCount: Int, expands: Bool, theme: Theme) {
    self.runIndex = runIndex
    self.lineCount = lineCount
    self.expands = expands
    self.theme = theme
    super.init(frame: .zero)
    title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    focusRingType = .exterior
    // A button without a title would otherwise not tell VoiceOver what it is.
    setAccessibilityElement(true)
    guard expands else {
      setAccessibilityRole(.staticText)
      return
    }
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
    switch (expands, paneName()) {
    case (true, nil):
      String(
        localized: "\(lineCount) unchanged lines, collapsed", bundle: .module,
        comment: "VoiceOver: the bar that stands for unchanged lines that are hidden.")
    case (true, let paneName?):
      String(
        localized: "\(lineCount) unchanged lines in \(paneName), collapsed", bundle: .module,
        comment:
          "VoiceOver: the bar that stands for unchanged lines that are hidden in a pane, such as Base."
      )
    case (false, nil):
      String(
        localized: "\(lineCount) lines not in the patch", bundle: .module,
        comment: "VoiceOver: the bar that stands for lines that a patch passes over.")
    case (false, let paneName?):
      String(
        localized: "\(lineCount) lines not in the patch, in \(paneName)", bundle: .module,
        comment:
          "VoiceOver: the bar that stands for lines that a patch passes over, in a pane such as Left."
      )
    }
  }

  /// The text of the bar.
  var label: String {
    expands
      ? String(
        localized: "\(lineCount) Unchanged Lines", bundle: .module,
        comment: "The bar that stands for unchanged lines that are hidden.")
      : String(
        localized: "\(lineCount) Lines Not in the Patch", bundle: .module,
        comment: "The bar that stands for lines that a patch passes over, which it does not hold.")
  }

  /// A bar of lines the pane does not have never takes the focus, as text does not.
  override var acceptsFirstResponder: Bool {
    expands && super.acceptsFirstResponder
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
    if ellipsis == nil {
      ellipsis = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(textStyle: Theme.collapsedRunTextStyle)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    }
    if let symbol = ellipsis {
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

  /// Gives the pane the focus, then tracks the click as a button does, if the bar expands.
  override func mouseDown(with event: NSEvent) {
    focusPane()
    if expands {
      super.mouseDown(with: event)
    }
  }

  override func drawFocusRingMask() {
    bounds.fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  /// Presses the bar for Return and Enter too, not only for Space, while it has focus.
  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers {
    case "\r" where expands, "\u{3}" where expands:
      performClick(self)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    guard expands else { return false }
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
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // A bar partly below the visible text, where a scroller may lie, shows only the part above
    // it.
    clipsToBounds = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }
}
