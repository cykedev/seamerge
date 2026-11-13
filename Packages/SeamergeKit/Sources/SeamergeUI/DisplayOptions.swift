import AppKit
import PaneKit

/// The accessibility settings of the system that change how the window draws, moves and takes
/// the keyboard.
///
/// The window reads them in one place and passes them on, so that each can be set on its own,
/// as the pictures for review and the tests do. The surfaces of the window come from the system,
/// which reduces their transparency itself.
struct DisplayOptions: Hashable {
  /// Whether colors take their values for increased contrast.
  var increasesContrast = false

  /// Whether marks that differ in color differ in shape as well.
  var differentiatesWithoutColor = false

  /// Whether translucent surfaces are drawn opaque.
  var reducesTransparency = false

  /// Whether movement gives way to cross-fades and cuts.
  var reducesMotion = false

  /// Whether Tab and the arrow keys reach every control, as Keyboard Navigation in the
  /// settings of the system asks: the toggles of the result take the focus then.
  var navigatesWithKeyboard = false

  /// The settings of the system as `workspace` reports them now.
  @MainActor
  static func current(in workspace: NSWorkspace) -> DisplayOptions {
    DisplayOptions(
      increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
      differentiatesWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
      reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
      reducesMotion: workspace.accessibilityDisplayShouldReduceMotion,
      navigatesWithKeyboard: NSApplication.shared.isFullKeyboardAccessEnabled)
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
