import AppKit

/// Learns what the user does in the decision column of a pane.
@MainActor
public protocol DecisionColumnDelegate: AnyObject {
  /// Tells the delegate that the user switched toggle `toggle` of `block`, with a click, the
  /// keyboard or VoiceOver.
  ///
  /// The column keeps showing the decisions it has; to show the outcome, give it new ones.
  func decisionColumn(_ column: DecisionColumnView, didSwitchToggle toggle: Int, ofBlock block: Int)

  /// Tells the delegate that the user asked to reset `block` to how it was loaded, with the arrow
  /// beside its toggles.
  func decisionColumn(_ column: DecisionColumnView, didAskToResetBlock block: Int)
}
