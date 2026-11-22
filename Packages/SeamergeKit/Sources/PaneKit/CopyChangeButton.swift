package import AppKit

/// The button at a seam that copies a changed block to the pane on one side: an arrow that
/// points to the side that changes, or a bin where the copy removes the lines of that side.
///
/// It draws its own face, quietly filled while it is pressed, and leaves tracking and
/// accessibility to `NSButton`. It takes no keyboard focus: the menu command and its keys do the
/// same.
package final class CopyChangeButton: NSButton {
  /// The block that the button copies, by its index in the panes' content.
  package let block: Int

  /// The side that the button copies to.
  package let direction: PaneSeam.CopyDirection

  /// Whether the copy removes the lines of the side it copies to, as the other side has none
  /// in the block.
  package internal(set) var removesLines = false {
    didSet {
      if removesLines != oldValue {
        needsDisplay = true
        show(text)
      }
    }
  }

  /// What the button is called, for copying and for removing lines.
  private var text: PaneSeam.CopyText

  /// How far the middle of the symbol lies from the middle of the button, rightward and
  /// downward, which keeps the click area within the seam while the symbol stands where it
  /// belongs.
  package internal(set) var symbolOffset = CGSize.zero {
    didSet {
      if symbolOffset != oldValue {
        needsDisplay = true
      }
    }
  }

  /// The size the symbol may take at most, which it is drawn smaller to keep.
  var largestSymbolSize = CGSize(
    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
  {
    didSet {
      if largestSymbolSize != oldValue {
        needsDisplay = true
      }
    }
  }

  /// Whether the block is the current one, whose symbol stands out.
  var isCurrent = false {
    didSet {
      if isCurrent != oldValue {
        needsDisplay = true
      }
    }
  }

  /// The colors and fonts of the seam.
  var theme: Theme {
    didSet { needsDisplay = true }
  }

  /// The symbols as images, made once rather than on every step of scrolling.
  private let symbols: SymbolImages

  init(
    block: Int, direction: PaneSeam.CopyDirection, theme: Theme, symbols: SymbolImages,
    text: PaneSeam.CopyText
  ) {
    self.block = block
    self.direction = direction
    self.theme = theme
    self.symbols = symbols
    self.text = text
    super.init(frame: .zero)
    title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    refusesFirstResponder = true
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    show(text)
  }

  /// Buttons are never archived.
  package required init?(coder: NSCoder) {
    nil
  }

  /// Names the button for VoiceOver and its help tag, as it copies or removes lines.
  func show(_ text: PaneSeam.CopyText) {
    self.text = text
    toolTip = removesLines ? text.removalToolTip : text.toolTip
    setAccessibilityLabel(
      String.localizedStringWithFormat(
        removesLines ? text.removalTitleFormat : text.titleFormat, block + 1))
    setAccessibilityHelp(removesLines ? text.removalHelp : text.help)
  }

  package override var isFlipped: Bool { true }

  package override var isHighlighted: Bool {
    didSet {
      if isHighlighted != oldValue {
        needsDisplay = true
      }
    }
  }

  package override func draw(_ dirtyRect: NSRect) {
    if isHighlighted {
      theme.pressedDecisionControlFill.setFill()
      NSBezierPath(
        roundedRect: bounds, xRadius: Theme.resetCornerRadius, yRadius: Theme.resetCornerRadius
      ).fill()
    }
    guard
      let symbol = symbols.image(
        named: symbolName, pointSize: theme.copySymbolSize, weight: .semibold,
        color: !isEnabled
          ? Theme.disabledMarkColor : isCurrent ? Theme.textColor : Theme.secondaryMarkColor)
    else { return }
    symbol.draw(in: symbolFrame(of: symbol))
  }

  /// Where `symbol` is drawn: in the middle of the button, moved by ``symbolOffset``, its
  /// origin on a pixel of the screen.
  private func symbolFrame(of symbol: NSImage) -> CGRect {
    let size = symbolSize(of: symbol)
    let scale = window?.backingScaleFactor ?? 2
    return CGRect(
      x: (((bounds.width - size.width) / 2 + symbolOffset.width) * scale).rounded() / scale,
      y: (((bounds.height - size.height) / 2 + symbolOffset.height) * scale).rounded() / scale,
      width: size.width, height: size.height)
  }

  /// The size `symbol` is drawn at: its own, made smaller where it is higher than it may be.
  private func symbolSize(of symbol: NSImage) -> CGSize {
    let size = symbol.size
    guard size.width > 0, size.height > 0 else { return size }
    let factor = min(
      largestSymbolSize.width / size.width, largestSymbolSize.height / size.height, 1)
    return CGSize(width: size.width * factor, height: size.height * factor)
  }

  /// Where the symbol is drawn, in the button, for the checks of its room.
  package var drawnSymbolFrame: CGRect {
    symbols.image(
      named: symbolName, pointSize: theme.copySymbolSize, weight: .semibold,
      color: Theme.secondaryMarkColor
    ).map(symbolFrame(of:)) ?? .zero
  }

  /// The name of the symbol: the bin, or the arrow toward the side the button copies to.
  var symbolName: String {
    if removesLines { return "trash" }
    return direction == .toRight ? "arrow.right" : "arrow.left"
  }

  package override func accessibilityPerformPress() -> Bool {
    performClick(self)
    return true
  }
}
