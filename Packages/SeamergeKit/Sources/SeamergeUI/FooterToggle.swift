import AppKit
import MergeModel

/// A toggle of the footer of a session window: what it switches, how it shows itself, and the
/// command it sends, which the main menu offers as well.
enum FooterToggle: CaseIterable {
  /// Shows spaces, tabs and line endings, or hides them.
  case invisibles

  /// Wraps long lines at the width of the panes, or lets them run on.
  case lineWrapping

  /// Collapses long runs of unchanged lines, or shows every line.
  case collapsedLines

  /// Couples the panes while they scroll, or lets each scroll on its own.
  case scrollSynchronization

  /// Shows the pane of the base, or hides it.
  case base

  /// The command that a click sends while the toggle is in `state`.
  ///
  /// The toggle of the collapsed lines sends one of two commands: Show All Lines while every
  /// run is collapsed, and Collapse Unchanged Lines otherwise, so that a click on a toggle in
  /// the mixed state collapses every run.
  func command(in state: NSControl.StateValue) -> SessionCommand {
    switch self {
    case .invisibles: .toggleInvisibles
    case .lineWrapping: .toggleLineWrapping
    case .collapsedLines: state == .on ? .showAllLines : .collapseUnchangedLines
    case .scrollSynchronization: .toggleScrollSynchronization
    case .base: .toggleBase
    }
  }

  /// The name of the symbol that the toggle shows.
  var symbolName: String {
    switch self {
    case .invisibles: "paragraphsign"
    case .lineWrapping: "arrow.turn.down.left"
    case .collapsedLines: "rectangle.compress.vertical"
    case .scrollSynchronization: "arrow.up.arrow.down"
    case .base: "rectangle.split.3x1"
    }
  }

  /// What VoiceOver calls the toggle: the name of its command in the menu, for the base its
  /// name.
  var accessibilityLabel: String {
    switch self {
    case .invisibles:
      String(
        localized: "Invisibles", bundle: .module,
        comment: "VoiceOver: the footer toggle that shows spaces, tabs and line endings.")
    case .lineWrapping: SessionCommand.toggleLineWrapping.title
    case .collapsedLines: SessionCommand.collapseUnchangedLines.title
    case .scrollSynchronization: SessionCommand.toggleScrollSynchronization.title
    case .base: Role.base.letter
    }
  }

  /// What VoiceOver says about the state of the toggle.
  func accessibilityValue(in state: NSControl.StateValue) -> String {
    switch (self, state) {
    case (.collapsedLines, .mixed):
      String(
        localized: "Some lines shown", bundle: .module,
        comment: "VoiceOver: the footer toggle of collapsed lines while some runs are expanded.")
    case (.collapsedLines, .on):
      String(
        localized: "Collapsed", bundle: .module,
        comment: "VoiceOver: the footer toggle of collapsed lines while every run is collapsed.")
    case (.collapsedLines, _):
      String(
        localized: "Every line shown", bundle: .module,
        comment: "VoiceOver: the footer toggle of collapsed lines while no run is collapsed.")
    case (_, .on):
      String(localized: "On", bundle: .module, comment: "VoiceOver: a footer toggle that is on.")
    default:
      String(localized: "Off", bundle: .module, comment: "VoiceOver: a footer toggle that is off.")
    }
  }

  /// The help tag of the toggle while it cannot act: what it does, and in parentheses why it
  /// cannot now, where the window shows a single column or else has no lines.
  func disabledHelp(showsSingleColumn: Bool) -> String {
    switch self {
    case .scrollSynchronization where showsSingleColumn:
      String(
        localized: "Synchronize scrolling (a single column scrolls alone)", bundle: .module,
        comment: "Help tag of the footer toggle of synchronized scrolling in a single column.")
    case .invisibles:
      String(
        localized: "Show invisible characters (no lines to show)", bundle: .module,
        comment: "Help tag of the footer toggle of invisibles in a window without lines.")
    case .lineWrapping:
      String(
        localized: "Wrap long lines (no lines to show)", bundle: .module,
        comment: "Help tag of the footer toggle of line wrapping in a window without lines.")
    case .collapsedLines:
      String(
        localized: "Collapse unchanged lines (none in this file)", bundle: .module,
        comment: "Help tag of the footer toggle of collapsed lines in a file without long runs.")
    case .scrollSynchronization:
      String(
        localized: "Synchronize scrolling (no lines to scroll)", bundle: .module,
        comment:
          "Help tag of the footer toggle of synchronized scrolling in a window without lines.")
    case .base:
      String(
        localized: "Show or hide the base (restore the layout first)", bundle: .module,
        comment: "Help tag of the footer toggle of the base while the result fills the window.")
    }
  }

  /// The help tag of the toggle in `state`: what a click does now.
  func help(in state: NSControl.StateValue) -> String {
    switch (self, state == .on) {
    case (.invisibles, false):
      String(
        localized: "Show spaces, tabs and line endings", bundle: .module,
        comment: "Help tag of the footer toggle of invisibles while they are hidden.")
    case (.invisibles, true):
      String(
        localized: "Hide spaces, tabs and line endings", bundle: .module,
        comment: "Help tag of the footer toggle of invisibles while they are shown.")
    case (.lineWrapping, false):
      String(
        localized: "Wrap long lines at the width of the panes", bundle: .module,
        comment: "Help tag of the footer toggle of line wrapping while lines run on.")
    case (.lineWrapping, true):
      String(
        localized: "Let long lines run on beyond the edge", bundle: .module,
        comment: "Help tag of the footer toggle of line wrapping while lines wrap.")
    case (.collapsedLines, false):
      String(
        localized: "Hide long runs of unchanged lines behind a bar", bundle: .module,
        comment: "Help tag of the footer toggle of collapsed lines while runs can collapse.")
    case (.collapsedLines, true):
      String(
        localized: "Show every line", bundle: .module,
        comment: "Help tag of the footer toggle of collapsed lines while every run is collapsed.")
    case (.scrollSynchronization, false):
      String(
        localized: "Scroll the panes together", bundle: .module,
        comment: "Help tag of the footer toggle of synchronized scrolling while it is off.")
    case (.scrollSynchronization, true):
      String(
        localized: "Let each pane scroll on its own", bundle: .module,
        comment: "Help tag of the footer toggle of synchronized scrolling while it is on.")
    case (.base, false):
      String(
        localized: "Show the base between A and B", bundle: .module,
        comment: "Help tag of the footer toggle of the base while the base is hidden.")
    case (.base, true):
      String(
        localized: "Hide the base and give A and B its room", bundle: .module,
        comment: "Help tag of the footer toggle of the base while the base is shown.")
    }
  }
}
