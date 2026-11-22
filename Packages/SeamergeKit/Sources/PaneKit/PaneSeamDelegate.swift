import AppKit

/// Learns what the user does at the seam between two panes.
@MainActor
package protocol PaneSeamDelegate: AnyObject {
  /// Tells the delegate that the user pressed the button that copies `block` in `direction`,
  /// with a click or VoiceOver.
  ///
  /// The seam shows the blocks it has; to show the outcome, give the panes new content.
  func seam(_ seam: PaneSeam, didAskToCopyBlock block: Int, in direction: PaneSeam.CopyDirection)
}
