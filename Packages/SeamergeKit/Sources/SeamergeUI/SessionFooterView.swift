import AppKit
import PaneKit

/// The footer of a session window: on the leading side the comparison mode in a pop-up button,
/// beside it the toggles of how the panes show the files.
///
/// It answers how the files are compared and shown now, and changes that quickly. Every entry
/// sends the action of a command of the window, which the main menu offers with its key
/// equivalent as well; the footer keeps no state of its own and shows what the window tells it.
///
/// The footer stands in the bottom border of the window, which the system draws; it has no
/// surface of its own. When the window gets narrow, the pop-up button shortens its title; the
/// symbols stay.
@MainActor
final class SessionFooterView: NSView {
  /// What the footer shows: the comparison mode and the state of each toggle.
  struct State: Equatable {
    /// The command of the comparison mode in effect.
    var mode: SessionCommand

    /// Whether the comparison mode can change now.
    var canChangeMode: Bool

    /// The state of each toggle of the footer, and whether it can act now.
    var toggles: [FooterToggle: Toggle]

    /// The state of a toggle.
    struct Toggle: Equatable {
      /// On, off, or mixed for the collapsed lines while some runs are expanded.
      var state: NSControl.StateValue

      /// Whether a click acts now.
      var isEnabled: Bool
    }
  }

  /// The commands of the comparison modes, in the order the pop-up button lists them.
  static let modeCommands: [SessionCommand] = [
    .compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges, .ignoreAllWhitespace,
  ]

  private let comparisonButton = NSPopUpButton(frame: .zero, pullsDown: false)
  private let toggleButtons: [(toggle: FooterToggle, button: FooterToggleButton)]

  /// The theme of the panes, whose outline of the toggles the mixed state takes.
  var theme = Theme() {
    didSet {
      for (_, button) in toggleButtons {
        button.outlineColor = theme.toggleOutlineColor
      }
    }
  }

  /// Creates a footer with `toggles`, in their order.
  init(toggles: [FooterToggle]) {
    toggleButtons = toggles.map { ($0, Self.button(for: $0)) }
    super.init(frame: CGRect(x: 0, y: 0, width: 400, height: WindowMetrics.footerHeight))
    comparisonButton.controlSize = .small
    comparisonButton.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
    comparisonButton.toolTip = SessionCommand.comparisonModeHelp
    comparisonButton.setAccessibilityLabel(SessionCommand.comparisonModeLabel)
    (comparisonButton.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    for command in Self.modeCommands {
      let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
      item.toolTip = command.help
      comparisonButton.menu?.addItem(item)
    }
    addSubview(comparisonButton)
    for (_, button) in toggleButtons {
      addSubview(button)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(
      String(
        localized: "Footer", bundle: .module,
        comment: "VoiceOver: the footer with the comparison mode and the view toggles."))
  }

  /// Footers are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The toggles of the footer, in their order.
  var toggles: [FooterToggle] {
    toggleButtons.map(\.toggle)
  }

  /// The button of `toggle`, if the footer has it.
  func button(of toggle: FooterToggle) -> NSButton? {
    toggleButtons.first { $0.toggle == toggle }?.button
  }

  /// The pop-up button of the comparison mode.
  var comparisonModeButton: NSPopUpButton {
    comparisonButton
  }

  /// Shows `state`: the comparison mode, and each toggle with the command a click sends now.
  func show(_ state: State) {
    if let index = Self.modeCommands.firstIndex(of: state.mode),
      comparisonButton.indexOfSelectedItem != index
    {
      comparisonButton.selectItem(at: index)
    }
    comparisonButton.isEnabled = state.canChangeMode
    for (toggle, button) in toggleButtons {
      let toggleState = state.toggles[toggle] ?? State.Toggle(state: .off, isEnabled: false)
      button.state = toggleState.state
      button.isEnabled = toggleState.isEnabled
      button.contentTintColor =
        toggleState.isEnabled ? Self.symbolColor(in: toggleState.state) : .disabledControlTextColor
      button.action = toggle.command(in: toggleState.state).action
      button.toolTip =
        toggleState.isEnabled ? toggle.help(in: toggleState.state) : toggle.disabledHelp
      button.setAccessibilityValueDescription(toggle.accessibilityValue(in: toggleState.state))
    }
    needsLayout = true
  }

  /// The narrowest the footer gets with everything in view: the pop-up button at the width of
  /// its longest title and the toggles beside it.
  var minimumWidth: CGFloat {
    WindowMetrics.footerInset * 2 + comparisonButton.intrinsicContentSize.width
      + WindowMetrics.footerGroupSpacing + togglesWidth
  }

  override func layout() {
    super.layout()
    let room =
      bounds.width - WindowMetrics.footerInset * 2 - WindowMetrics.footerGroupSpacing
      - togglesWidth
    var x = WindowMetrics.footerInset
    let popUpWidth = min(comparisonButton.intrinsicContentSize.width, max(room, 0))
    place(comparisonButton, x: x, width: popUpWidth)
    x += popUpWidth + WindowMetrics.footerGroupSpacing
    // The toggles take the height of the pop-up button, so that all controls share one middle
    // and one height.
    let height = comparisonButton.intrinsicContentSize.height
    for (_, button) in toggleButtons {
      place(button, x: x, width: toggleWidth, height: height)
      x += toggleWidth + WindowMetrics.footerToggleSpacing
    }
  }

  /// Places `control` at `x` with `width` and `height`, its own unless given, centered in the
  /// height of the footer, on whole points.
  private func place(_ control: NSControl, x: CGFloat, width: CGFloat, height: CGFloat? = nil) {
    let height = height ?? control.intrinsicContentSize.height
    control.frame = backingAlignedRect(
      CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: width, height: height),
      options: .alignAllEdgesNearest)
  }

  /// The width of the toggles side by side.
  private var togglesWidth: CGFloat {
    let count = CGFloat(toggleButtons.count)
    return toggleWidth * count + WindowMetrics.footerToggleSpacing * max(count - 1, 0)
  }

  /// The width of every toggle: room for the widest symbol, and no less than the standard
  /// width, so that the symbols stand evenly.
  private var toggleWidth: CGFloat {
    let widest = toggleButtons.map { $0.button.image?.size.width ?? 0 }.max() ?? 0
    let needed = widest + 2 * WindowMetrics.footerSymbolPadding
    return max(WindowMetrics.footerSymbolButtonWidth, needed.rounded(.up))
  }

  /// The color of the symbol of a toggle in `state` that can act.
  ///
  /// It is the accent color while the toggle is on, as the toggles in the bars of a window show
  /// it, and secondary while it is off or mixed. A toggle that cannot act is dimmed as any
  /// control is.
  static func symbolColor(in state: NSControl.StateValue) -> NSColor {
    state == .on ? onSymbolColor : .secondaryLabelColor
  }

  /// The accent color of the user, a shade darker in light appearances and lighter in dark
  /// ones, so that the symbol of a toggle that is on keeps 3:1 on its gray area.
  static let onSymbolColor = NSColor(name: nil) { appearance in
    var accent = NSColor.controlAccentColor
    appearance.performAsCurrentDrawingAppearance {
      accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? accent
    }
    let match = appearance.bestMatch(from: [
      .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ])
    let (fraction, toward): (CGFloat, NSColor) =
      switch match {
      case .darkAqua: (0.35, .white)
      case .accessibilityHighContrastDarkAqua: (0.5, .white)
      case .accessibilityHighContrastAqua: (0.3, .black)
      default: (0.15, .black)
      }
    return accent.blended(withFraction: fraction, of: toward) ?? accent
  }

  /// The button of `toggle`: a standard toggle with its symbol, which sends its command along
  /// the responder chain.
  private static func button(for toggle: FooterToggle) -> FooterToggleButton {
    let image = NSImage(
      systemSymbolName: toggle.symbolName, accessibilityDescription: toggle.accessibilityLabel)
    let button = FooterToggleButton(title: "", image: image ?? NSImage(), target: nil, action: nil)
    button.setButtonType(.pushOnPushOff)
    button.isBordered = false
    button.controlSize = .small
    button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
    button.imagePosition = .imageOnly
    button.allowsMixedState = toggle == .collapsedLines
    button.setAccessibilityLabel(toggle.accessibilityLabel)
    return button
  }
}

/// A toggle of the footer: a borderless button with a quiet gray area behind its symbol while
/// it is on.
///
/// The symbol takes the accent color while the toggle is on. In the mixed state, where only
/// some of what it switches is on, an outline of the same shape stands around a secondary
/// symbol. On, mixed and off thus differ without color too: an area, an outline, nothing.
@MainActor
final class FooterToggleButton: NSButton {
  /// The color of the outline in the mixed state.
  var outlineColor = Theme().toggleOutlineColor {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    let radius = WindowMetrics.footerToggleCornerRadius
    switch state {
    case .on:
      Self.onFill.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    case .mixed:
      let width = WindowMetrics.footerToggleOutlineWidth
      let outline = NSBezierPath(
        roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius - width / 2,
        yRadius: radius - width / 2)
      outline.lineWidth = width
      outlineColor.setStroke()
      outline.stroke()
    default:
      break
    }
    super.draw(dirtyRect)
  }

  /// The gray area behind a toggle that is on.
  static var onFill: NSColor { .secondarySystemFill }
}
