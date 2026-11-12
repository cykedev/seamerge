import AppKit

extension Theme {
  /// The color behind the text and the gutter.
  public static var backgroundColor: NSColor { .textBackgroundColor }

  /// The color of the code.
  public static var textColor: NSColor { .textColor }

  /// The color of the line numbers of the current block, whose cells are filled.
  public static var currentLineNumberColor: NSColor { .labelColor }

  /// The color of marks that say something without a role: the ring of an ignored difference
  /// and the mark of a resolved conflict.
  public static var secondaryMarkColor: NSColor { .secondaryLabelColor }

  /// The color of the line numbers: quieter than the code, yet as legible as any text.
  public var lineNumberColor: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.lineNumberOpacity[appearance])
    }
  }

  /// The color of the preview of a conflict in the result: quieter than real text, yet legible
  /// on every row tint of A and B.
  public var previewTextColor: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.previewTextOpacity[appearance])
    }
  }

  /// The color of the invisible characters: quiet beside the code, yet legible on every tint and
  /// within a selection.
  public var invisibleCharacterColor: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.invisibleCharacterOpacity[appearance])
    }
  }

  /// The tone behind the marks of the overview bar, drawn over the text background.
  public var overviewBackgroundTone: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.overviewBackgroundOpacity[appearance])
    }
  }

  /// The quiet tone of the bar of a collapsed run, drawn over the text background.
  public var collapsedRunFill: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.collapsedRunOpacity[appearance])
    }
  }

  /// The tone of the bar of a collapsed run while it is pressed, drawn over the text background.
  public var pressedCollapsedRunFill: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.pressedCollapsedRunOpacity[appearance])
    }
  }

  /// The color of the ellipsis and the label on the bar of a collapsed run: secondary beside the
  /// code, yet as legible as any text, also within a selection.
  public var collapsedRunTextColor: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.collapsedRunTextOpacity[appearance])
    }
  }

  /// The light area of the overview bar that shows the visible part of the text.
  public var visibleRegionFill: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.visibleRegionOpacity[appearance])
    }
  }

  /// The outline of the visible area in the overview bar.
  public var visibleRegionOutline: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.visibleRegionOutlineOpacity[appearance])
    }
  }

  /// The color of the mark of a block of `style` in the overview bar: the symbol value of the
  /// side whose text the rows hold, a neutral tone for text typed by hand.
  public func overviewMarkColor(for style: BlockStyle) -> NSColor {
    switch style {
    case .tinted(let role): symbolColor(for: role)
    case .original: symbolColor(for: .base)
    case .combined:
      color { appearance, _ in
        NSColor(rgb: Palette.symbol(of: .a)[appearance])
          .blended(withFraction: 0.5, of: NSColor(rgb: Palette.symbol(of: .b)[appearance]))
          ?? NSColor(rgb: Palette.symbol(of: .a)[appearance])
      }
    case .unchanged, .handwritten: Self.secondaryMarkColor
    }
  }

  /// The color of a toggle or a letter of a state sign that stands for `roles`: the color of the
  /// side, of both sides blended where they share it, or of the base alone.
  public func decisionColor(for roles: [ColorRole]) -> NSColor {
    let sides = roles.filter { $0 == .a || $0 == .b }
    switch sides.count {
    case 0: return symbolColor(for: .base)
    case 1: return symbolColor(for: sides[0])
    default: return overviewMarkColor(for: .combined)
    }
  }

  /// The color of the label on a filled toggle or letter: white in light appearances, black in
  /// dark ones, where the fills are light.
  public var filledLabelColor: NSColor {
    color { appearance, _ in
      switch appearance {
      case .light, .lightHighContrast: .white
      case .dark, .darkHighContrast: .black
      }
    }
  }

  /// The quiet fill behind a toggle or the reset arrow while it is pressed.
  public var pressedDecisionControlFill: NSColor {
    color { appearance, nsAppearance in
      NSColor.labelColor.resolved(in: nsAppearance)
        .withAlphaComponent(Palette.pressedCollapsedRunOpacity[appearance])
    }
  }

  /// The symbol value of `role`: the color of its markers, badges and toggles.
  public func symbolColor(for role: ColorRole) -> NSColor {
    let values = Palette.symbol(of: role)
    return color { appearance, _ in NSColor(rgb: values[appearance]) }
  }

  /// The color of the change marker and of the marks of removed text in a block of `style`: the
  /// color of the side that made the change.
  public func markerColor(for style: BlockStyle) -> NSColor {
    if case .tinted(let role) = style {
      return symbolColor(for: role)
    }
    return Self.secondaryMarkColor
  }

  /// The color of the mark of a conflict.
  public func color(for conflict: ConflictMarker) -> NSColor {
    switch conflict {
    case .open: symbolColor(for: .conflict)
    case .resolved: Self.secondaryMarkColor
    }
  }

  /// The fill behind a row, or `nil` if the row stays on the text background.
  ///
  /// Filler rows are tinted at half the strength of their block, and the rows of the current
  /// block more strongly, so that it stands out on every pane; where the block leaves a pane
  /// untinted, its rows get a quiet neutral tone while it is current.
  public func rowFill(for style: BlockStyle, isFiller: Bool, isCurrent: Bool) -> NSColor? {
    guard let tint = tint(for: style) ?? (isCurrent ? .quiet : nil) else { return nil }
    let factor = Self.rowFactor(isFiller: isFiller, isCurrent: isCurrent)
    return color { appearance, nsAppearance in
      tint.color(appearance, nsAppearance)
        .withAlphaComponent(tint.rowOpacity(appearance) * factor)
    }
  }

  /// The fill behind a changed run within a line of a block of `style`, drawn over the row fill,
  /// or `nil` if such runs are not highlighted.
  ///
  /// Together with the row fill of a line, current or not, the run reaches the run opacity of
  /// the palette, so that text on it stays legible in the current block too.
  public func runFill(for style: BlockStyle, isCurrent: Bool) -> NSColor? {
    guard let tint = tint(for: style), tint.highlightsRuns else { return nil }
    let factor = Self.rowFactor(isFiller: false, isCurrent: isCurrent)
    return color { appearance, nsAppearance in
      let row = tint.rowOpacity(appearance) * factor
      let overlay = max(Palette.runOpacity[appearance] - row, 0) / (1 - row)
      return tint.color(appearance, nsAppearance).withAlphaComponent(overlay)
    }
  }

  /// The fill of the selection, translucent so that the tint of a row stays visible below it:
  /// in the accent color while the pane has focus in the key window, quieter otherwise.
  public func selectionFill(isEmphasized: Bool) -> NSColor {
    color { appearance, nsAppearance in
      (isEmphasized
        ? NSColor.selectedTextBackgroundColor
        : NSColor.unemphasizedSelectedTextBackgroundColor)
        .resolved(in: nsAppearance)
        .withAlphaComponent(Palette.selectionOpacity[appearance])
    }
  }

  /// A color that takes the value that `resolve` gives for the appearance it is drawn in, with
  /// increased contrast if the theme asks for it.
  private func color(
    _ resolve: @escaping @Sendable (PaletteAppearance, NSAppearance) -> NSColor
  ) -> NSColor {
    let increasesContrast = increasesContrast
    return NSColor(name: nil) { appearance in
      resolve(PaletteAppearance(appearance, increasesContrast: increasesContrast), appearance)
    }
  }

  private static func rowFactor(isFiller: Bool, isCurrent: Bool) -> CGFloat {
    (isCurrent ? Palette.currentBlockFactor : 1) * (isFiller ? Palette.fillerFactor : 1)
  }

  /// The tint that a style stands for.
  private func tint(for style: BlockStyle) -> Tint? {
    switch style {
    case .unchanged: nil
    case .tinted(.conflict): .openConflict
    case .tinted(let role): .role(role)
    case .original: .role(.base)
    case .combined: .combined
    case .handwritten: .handwritten
    }
  }
}

/// The color family that a row is tinted in, with the strength of its fill.
private enum Tint {
  case role(ColorRole)
  case openConflict
  case combined
  /// The neutral tone of the rows of the current block on a pane that the block leaves untinted.
  case quiet
  case handwritten

  /// The opaque color that the fills are derived from.
  func color(_ appearance: PaletteAppearance, _ nsAppearance: NSAppearance) -> NSColor {
    switch self {
    case .role(let role): NSColor(rgb: Palette.surface(of: role)[appearance])
    case .openConflict: NSColor(rgb: Palette.surface(of: .conflict)[appearance])
    case .combined:
      NSColor(rgb: Palette.surface(of: .a)[appearance])
        .blended(withFraction: 0.5, of: NSColor(rgb: Palette.surface(of: .b)[appearance]))
        ?? NSColor(rgb: Palette.surface(of: .a)[appearance])
    case .quiet, .handwritten: NSColor.labelColor.resolved(in: nsAppearance)
    }
  }

  /// The opacity of the color behind a row.
  func rowOpacity(_ appearance: PaletteAppearance) -> CGFloat {
    switch self {
    case .role(.base): Palette.rowOpacity[appearance] * Palette.baseStrength[appearance]
    case .role, .combined: Palette.rowOpacity[appearance]
    case .openConflict: Palette.rowOpacity[appearance] * Palette.openConflictStrength[appearance]
    case .quiet: Palette.quietOpacity[appearance]
    case .handwritten: Palette.handwrittenOpacity[appearance]
    }
  }

  /// Whether changed runs within the rows are highlighted: on the rows of a side, not on neutral
  /// or handwritten ones.
  var highlightsRuns: Bool {
    switch self {
    case .role, .combined, .openConflict: true
    case .quiet, .handwritten: false
    }
  }
}
