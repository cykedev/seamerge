import AppKit

/// The sheet Install the seamerge Command on the welcome window.
extension WelcomeWindowController {
  /// Whether the sheet of `tool` can be shown: while no other sheet hangs on the window.
  public func canShowCommandLineTool(_ tool: CommandLineTool) -> Bool {
    tool.sheet == nil && window?.attachedSheet == nil
  }

  /// Shows the window in front and on it the sheet of `tool`, which says what lies at the place
  /// of the command and offers to install, update or remove its link.
  public func showCommandLineTool(_ tool: CommandLineTool) {
    guard canShowCommandLineTool(tool), let window else { return }
    showWindow(nil)
    tool.presentSheet(on: window, colors: CompareFilesColors(displayOptions), announce: announce)
  }
}
