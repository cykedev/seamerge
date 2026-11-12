import AppKit
import PaneKit
import Testing

/// Checks every pair of text or sign and the surface it stands on, in every look: text needs
/// 4.5:1, signs 3:1.
///
/// Surfaces are composed in the order the pane draws them: text background, row fill, the fill
/// of a changed run, and the translucent selection on top.
@MainActor
@Suite struct ContrastTests {
  @Test(arguments: Look.all)
  func everyPairMeetsItsMinimumContrast(look: Look) {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let failures = pairs(theme: theme, appearance: look.appearance).compactMap {
      pair -> String? in
      let ratio = Contrast.ratio(pair.foreground, pair.surface)
      guard ratio < pair.minimum else { return nil }
      return "\(pair.description): \(String(format: "%.2f", ratio)) < \(pair.minimum)"
    }
    #expect(failures.isEmpty, "\(failures.joined(separator: "; "))")
  }

  /// The minimum contrast of text up to 17 points.
  private static let text: CGFloat = 4.5

  /// The minimum contrast of signs that say something.
  private static let sign: CGFloat = 3

  private static let styles: [BlockStyle] = [
    .unchanged, .tinted(.a), .tinted(.base), .tinted(.b), .tinted(.conflict), .original,
    .combined, .handwritten,
  ]

  private struct Pair {
    var description: String
    var foreground: NSColor
    var surface: NSColor
    var minimum: CGFloat
  }

  /// Every pair that a pane draws, with colors as drawn in `appearance`.
  private func pairs(theme: Theme, appearance: NSAppearance) -> [Pair] {
    let resolve = { (color: NSColor?) in Contrast.resolve(color, in: appearance) }
    let ground = Contrast.over(resolve(.textBackgroundColor), .white)
    var pairs: [Pair] = []
    for style in Self.styles {
      for isCurrent in [false, true] {
        let place = "\(style)\(isCurrent ? ", current" : "")"
        let rowFill = resolve(theme.rowFill(for: style, isFiller: false, isCurrent: isCurrent))
        let row = Contrast.over(rowFill, ground)
        let runFill = resolve(theme.runFill(for: style, isCurrent: isCurrent))
        var surfaces = [("row", row), ("changed run", Contrast.over(runFill, row))]
        for isEmphasized in [true, false] {
          let selection = resolve(theme.selectionFill(isEmphasized: isEmphasized))
          let name = isEmphasized ? "selection" : "inactive selection"
          surfaces.append((name, Contrast.over(selection, row)))
          surfaces.append(
            ("changed run in an \(name)", Contrast.over(selection, Contrast.over(runFill, row))))
        }
        for (surfaceName, surface) in surfaces {
          pairs.append(
            Pair(
              description: "text on \(surfaceName) of \(place)",
              foreground: Contrast.over(resolve(Theme.textColor), surface), surface: surface,
              minimum: Self.text))
          // An invisible character tells which line ending a line has.
          pairs.append(
            Pair(
              description: "invisible character on \(surfaceName) of \(place)",
              foreground: Contrast.over(resolve(theme.invisibleCharacterColor), surface),
              surface: surface, minimum: Self.sign))
        }
        // Marks of removed text stand on any surface of a side's text, with a seam of
        // background color around them that keeps them apart from a selection.
        if case .tinted(let role) = style, role == .a || role == .b {
          let mark = Contrast.over(resolve(theme.markerColor(for: style)), ground)
          for (surfaceName, surface) in surfaces.prefix(2) {
            pairs.append(
              Pair(
                description: "removal mark on \(surfaceName) of \(place)", foreground: mark,
                surface: surface, minimum: Self.sign))
          }
          pairs.append(
            Pair(
              description: "removal mark on its seam in \(place)", foreground: mark,
              surface: ground, minimum: Self.sign))
        }
        // The preview stands on rows tinted in the color of the side it comes from.
        if case .tinted(let role) = style, role == .a || role == .b {
          pairs.append(
            Pair(
              description: "preview text on row of \(place)",
              foreground: Contrast.over(resolve(theme.previewTextColor), row), surface: row,
              minimum: Self.text))
        }
        pairs += gutterPairs(
          theme: theme, style: style, isCurrent: isCurrent, ground: ground, resolve: resolve)
      }
    }
    return pairs + overviewPairs(theme: theme, ground: ground, resolve: resolve)
      + collapsedRunPairs(theme: theme, ground: ground, resolve: resolve)
      + decisionPairs(theme: theme, ground: ground, resolve: resolve)
  }

  /// The pairs in the decision column: the labels of toggles on and off, also while pressed, the
  /// letters of the state signs, and the symbols, all on the plain column.
  private func decisionPairs(
    theme: Theme, ground: NSColor, resolve: (NSColor?) -> NSColor?
  ) -> [Pair] {
    let pressed = Contrast.over(resolve(theme.pressedDecisionControlFill), ground)
    var pairs: [Pair] = []
    let toggles: [[ColorRole]] = [[.a], [.base], [.b], [.a, .b], [.base, .a], [.base, .b]]
    for roles in toggles {
      let color = theme.decisionColor(for: roles)
      let fill = Contrast.over(resolve(color), ground)
      let pressedFill = Contrast.over(resolve(theme.pressedDecisionControlFill), fill)
      for (name, surface) in [("", fill), ("pressed ", pressedFill)] {
        pairs.append(
          Pair(
            description: "label on \(name)toggle \(roles) that is on",
            foreground: Contrast.over(resolve(theme.filledLabelColor), surface),
            surface: surface, minimum: Self.text))
      }
      pairs.append(
        Pair(
          description: "label of toggle \(roles) that is off and outlined letter",
          foreground: Contrast.over(resolve(color), ground), surface: ground, minimum: Self.text))
      pairs.append(
        Pair(
          description: "label of pressed toggle \(roles) that is off",
          foreground: Contrast.over(resolve(Theme.textColor), pressed), surface: pressed,
          minimum: Self.text))
    }
    let symbols: [(String, NSColor)] = [
      ("trash can, pencil and reset arrow", Theme.secondaryMarkColor),
      ("warning sign", theme.symbolColor(for: .conflict)),
    ]
    for (name, color) in symbols {
      for (surfaceName, surface) in [("column", ground), ("pressed control", pressed)] {
        pairs.append(
          Pair(
            description: "\(name) on \(surfaceName)",
            foreground: Contrast.over(resolve(color), surface), surface: surface,
            minimum: Self.sign))
      }
    }
    return pairs
  }

  /// The pairs on the bar of a collapsed run: its label and ellipsis, on the bar and within a
  /// selection that takes in its rows.
  private func collapsedRunPairs(
    theme: Theme, ground: NSColor, resolve: (NSColor?) -> NSColor?
  ) -> [Pair] {
    let bar = Contrast.over(resolve(theme.collapsedRunFill), ground)
    var surfaces = [
      ("bar of a collapsed run", bar),
      (
        "pressed bar of a collapsed run",
        Contrast.over(resolve(theme.pressedCollapsedRunFill), ground)
      ),
    ]
    for isEmphasized in [true, false] {
      surfaces.append(
        (
          "\(isEmphasized ? "selection" : "inactive selection") on the bar of a collapsed run",
          Contrast.over(resolve(theme.selectionFill(isEmphasized: isEmphasized)), bar)
        ))
    }
    return surfaces.map { name, surface in
      Pair(
        description: "label on \(name)",
        foreground: Contrast.over(resolve(theme.collapsedRunTextColor), surface), surface: surface,
        minimum: Self.text)
    }
  }

  /// The pairs in the overview bar: every mark and the pointer at the current block, on the bar
  /// and within the area that shows the visible part.
  private func overviewPairs(
    theme: Theme, ground: NSColor, resolve: (NSColor?) -> NSColor?
  ) -> [Pair] {
    let bar = Contrast.over(resolve(theme.overviewBackgroundTone), ground)
    let visible = Contrast.over(resolve(theme.visibleRegionFill), bar)
    var pairs: [Pair] = []
    for (surfaceName, surface) in [("bar", bar), ("visible area", visible)] {
      for style in Self.styles where style != .unchanged {
        pairs.append(
          Pair(
            description: "overview mark of \(style) on \(surfaceName)",
            foreground: Contrast.over(resolve(theme.overviewMarkColor(for: style)), surface),
            surface: surface, minimum: Self.sign))
      }
      pairs.append(
        Pair(
          description: "current block pointer on \(surfaceName)",
          foreground: Contrast.over(resolve(.labelColor), surface), surface: surface,
          minimum: Self.sign))
    }
    return pairs
  }

  /// The pairs in the gutter beside the rows of a block of `style`: change and conflict marks,
  /// the ring and line numbers, on the plain gutter, and on the filled cells of the current
  /// block, with and without focus, where every mark and number takes the color of selected
  /// content.
  private func gutterPairs(
    theme: Theme, style: BlockStyle, isCurrent: Bool, ground: NSColor,
    resolve: (NSColor?) -> NSColor?
  ) -> [Pair] {
    var pairs: [Pair] = []
    guard !isCurrent else {
      for isEmphasized in [true, false] {
        let place = "current cell\(isEmphasized ? "" : " without focus")"
        let cell = Contrast.over(resolve(Theme.currentCellFill(isEmphasized: isEmphasized)), ground)
        let content = Contrast.over(
          resolve(Theme.currentCellContentColor(isEmphasized: isEmphasized)), cell)
        pairs.append(
          Pair(
            description: "line number in \(place)", foreground: content, surface: cell,
            minimum: Self.text))
      }
      return pairs
    }
    for isFiller in [false, true] {
      let place = "gutter of \(style)\(isFiller ? ", filler" : "")"
      func pair(_ name: String, _ color: NSColor, minimum: CGFloat) {
        pairs.append(
          Pair(
            description: "\(name) in \(place)", foreground: Contrast.over(resolve(color), ground),
            surface: ground, minimum: minimum))
      }
      if case .tinted(let role) = style, role == .a || role == .b {
        pair("change marker", theme.markerColor(for: style), minimum: Self.sign)
      }
      // The conflict mark stands on the base pane, or on B while the base is hidden.
      switch style {
      case .tinted(.conflict), .original, .tinted(.b):
        for conflict in ConflictMarker.allCases {
          pair("\(conflict) conflict mark", theme.color(for: conflict), minimum: Self.sign)
        }
      default:
        break
      }
      pair("ring", Theme.secondaryMarkColor, minimum: Self.sign)
      if !isFiller {
        pair("line number", theme.lineNumberColor, minimum: Self.text)
      }
    }
    return pairs
  }
}
