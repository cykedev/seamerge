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
