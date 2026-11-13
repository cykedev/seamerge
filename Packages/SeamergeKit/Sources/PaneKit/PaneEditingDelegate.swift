import AppKit

/// Decides every change of an editable pane's text before the pane carries it out.
///
/// Every edit the user makes, by typing, deleting, pasting, dragging, an input method or a dead
/// key, reaches the delegate before it changes the text. The delegate answers with the edits that
/// carry it out: usually the edit itself, sometimes edits around a preview, none to refuse it.
/// The pane carries out exactly what the delegate answers and then tells it what it replaced.
@MainActor
public protocol PaneEditingDelegate: AnyObject {
  /// The edits that carry out `edit`, which the user is about to make in `pane`, in order; each
  /// range refers to the text as the edits before it left it.
  ///
  /// Answer `[edit]` to let the edit through as it is, and no edits to refuse it. The edit's
  /// range refers to the text as it is now, which the pane's document view still shows.
  func pane(_ pane: PaneView, editsFor edit: PaneEdit) -> [PaneEdit]

  /// Tells the delegate that `pane` carried out `edits`, the answer to an edit of the user, and
  /// that they replaced `replacedTexts`, one for each edit.
  ///
  /// The pane has kept its rows, line numbers, blocks, previews and collapsed runs in step with
  /// the text as well as it can; give it the blocks, previews and row tints that the edits lead
  /// to with ``PaneView/setBlocks(_:previews:rowTints:)``, which keeps the text, the selection
  /// and the scroll position and draws only what changed.
  ///
  /// An action of the user on several selections, or text dragged within the view, is asked and
  /// reported edit by edit, so that each answer is taken over before the next question. The
  /// reports of one action follow each other within the same event, so an undo manager that
  /// groups by event, as a window's does, makes them one undo step.
  func pane(_ pane: PaneView, didCarryOut edits: [PaneEdit], replacing replacedTexts: [String])

  /// Tells the delegate that the text of `pane` changed by `edit` without having been announced,
  /// which only a bug elsewhere causes; the range of `edit` refers to the text before the change.
  ///
  /// The text that the edit replaced is gone by then. The pane calls this while its text
  /// processes the change: update what follows the text, but leave the pane's text and content
  /// alone until the change is over.
  func pane(_ pane: PaneView, didChangeTextWithoutAnnouncing edit: PaneEdit)
}
