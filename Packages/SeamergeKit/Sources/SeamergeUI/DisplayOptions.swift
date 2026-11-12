import AppKit
import PaneKit

/// The four accessibility settings of the system that change how the window draws and moves.
///
/// The window reads them in one place and passes them on, so that each can be set on its own,
/// as the pictures for review do. The surfaces of the window come from the system, which reduces
/// their transparency itself.
struct DisplayOptions: Hashable {
  /// Whether colors take their values for increased contrast.
  var increasesContrast = false

  /// Whether marks that differ in color differ in shape as well.
  var differentiatesWithoutColor = false

  /// Whether translucent surfaces are drawn opaque.
  var reducesTransparency = false

  /// Whether movement gives way to cross-fades and cuts.
  var reducesMotion = false

  /// The settings of the system as `workspace` reports them now.
  @MainActor
  static func current(in workspace: NSWorkspace) -> DisplayOptions {
    DisplayOptions(
      increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
      differentiatesWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
      reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
      reducesMotion: workspace.accessibilityDisplayShouldReduceMotion)
  }

  /// The theme of the panes with these settings, with code at its standard size.
  var theme: Theme {
    Theme(
      increasesContrast: increasesContrast, differentiatesWithoutColor: differentiatesWithoutColor)
  }

  /// The theme of the panes with these settings, with code of `fontSize` points.
  func theme(fontSize: CGFloat) -> Theme {
    var theme = theme
    theme.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    return theme
  }
}
