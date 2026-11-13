import AppKit

/// The small sign of a block's state in the decision column: outlined letters for sources the
/// merge took, filled letters for sources the user chose, a trash can for a block that takes
/// nothing, a pencil for work by hand, a warning sign for an open conflict.
@MainActor
struct StateSign {
  var state: BlockDecision.State
  var theme: Theme

  /// Draws the sign with its leading edge at `point.x`, centered on `point.y`.
  func draw(at point: CGPoint) {
    switch state {
    case .unchanged:
      break
    case .automatic(let roles):
      drawLetters(roles, filled: false, at: point)
    case .chosen(let roles) where roles.isEmpty:
      drawSymbol("trash", color: Theme.secondaryMarkColor, at: point)
    case .chosen(let roles):
      drawLetters(roles, filled: true, at: point)
    case .edited:
      drawSymbol("pencil", color: Theme.secondaryMarkColor, at: point)
    case .open:
      drawSymbol(
        "exclamationmark.triangle.fill", color: theme.symbolColor(for: .conflict), at: point)
    }
  }

  /// What VoiceOver says for the sign.
  var accessibilityLabel: String? {
    state.spokenName
  }

  /// What the sign means, as its help tag and the help that VoiceOver reads.
  var help: String? {
    switch state {
    case .unchanged:
      return nil
    case .automatic(let roles):
      let names = DecisionToggleButton.spokenNames(of: roles)
      return String(
        localized: "Takes the lines of \(names), as the merge decided", bundle: .module,
        comment: "Help tag of the sign of a block whose sources the merge took, such as A and B.")
    case .chosen(let roles) where roles.isEmpty:
      return String(
        localized: "Takes no lines, as you chose", bundle: .module,
        comment: "Help tag of the trash can: a block that takes no lines from any input.")
    case .chosen(let roles):
      let names = DecisionToggleButton.spokenNames(of: roles)
      return String(
        localized: "Takes the lines of \(names), in the order you chose", bundle: .module,
        comment: "Help tag of the sign of a block whose sources the user chose, such as B and A.")
    case .edited:
      return String(
        localized: "Holds lines that you typed or changed", bundle: .module,
        comment: "Help tag of the pencil: a block whose text the user typed or changed.")
    case .open:
      return MarkHelp.conflict(.open)
    }
  }

  /// The width of the sign.
  var width: CGFloat {
    switch state {
    case .unchanged: 0
    case .automatic(let roles),
      .chosen(let roles) where !roles.isEmpty:
      roles.map(letterWidth(of:)).reduce(0, +)
        + CGFloat(roles.count - 1) * Theme.stateSignSpacing
    default: Theme.stateSignHeight
    }
  }

  private func drawLetters(_ roles: [ColorRole], filled: Bool, at point: CGPoint) {
    var x = point.x
    let font = Self.font
    for role in roles {
      let width = letterWidth(of: role)
      let rect = CGRect(
        x: x, y: (point.y - Theme.stateSignHeight / 2).rounded(), width: width,
        height: Theme.stateSignHeight)
      let color = theme.decisionColor(for: [role])
      if filled {
        color.setFill()
        NSBezierPath(
          roundedRect: rect, xRadius: Theme.stateSignCornerRadius,
          yRadius: Theme.stateSignCornerRadius
        ).fill()
      } else {
        color.setStroke()
        // The line is centered on the path, so the path lies half its width inside.
        let inset = Theme.stateSignOutlineWidth / 2
        let outline = NSBezierPath(
          roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: Theme.stateSignCornerRadius,
          yRadius: Theme.stateSignCornerRadius)
        outline.lineWidth = Theme.stateSignOutlineWidth
        outline.stroke()
      }
      let label = NSAttributedString(
        string: DecisionToggleButton.name(of: role),
        attributes: [.font: font, .foregroundColor: filled ? theme.filledLabelColor : color])
      DecisionToggleButton.draw(
        label, at: rect.midX - label.size().width / 2, centeringCapitalsOn: rect.midY)
      x += width + Theme.stateSignSpacing
    }
  }

  private func drawSymbol(_ name: String, color: NSColor, at point: CGPoint) {
    guard
      let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    else { return }
    let size = symbol.size
    symbol.draw(
      in: CGRect(
        x: point.x, y: (point.y - size.height / 2).rounded(), width: size.width,
        height: size.height))
  }

  /// The width of the outline around the letter of `role`.
  private func letterWidth(of role: ColorRole) -> CGFloat {
    let label = NSAttributedString(
      string: DecisionToggleButton.name(of: role), attributes: [.font: Self.font])
    return max(
      (label.size().width + 2 * Theme.stateSignPadding).rounded(.up), Theme.stateSignHeight)
  }

  /// The size of the symbols, which fill the height of the sign like the outlined letters.
  private static var symbolPointSize: CGFloat {
    font.pointSize + Theme.stateSignSymbolSizeIncrease
  }

  /// The font of the letters.
  static var font: NSFont {
    .systemFont(
      ofSize: NSFont.preferredFont(forTextStyle: Theme.stateSignTextStyle).pointSize,
      weight: .semibold)
  }
}
