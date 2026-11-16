import AppKit
import PaneKit
import Testing

/// The search field of the find bar of `search`.
@MainActor
func findField(of search: PaneSearch) throws -> NSSearchField {
  let bar = try #require(search.findBar.findBarView)
  return try #require(subviews(of: bar).compactMap { $0 as? NSSearchField }.first)
}

/// Types or pastes `text` into `field` as the user would, over all it held.
@MainActor
func enter(_ text: String, into field: NSSearchField, in window: NSWindow) throws {
  window.makeFirstResponder(field)
  let editor = try #require(field.currentEditor() as? NSTextView)
  editor.selectAll(nil)
  editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
}

/// `view` and every view within it.
@MainActor
func subviews(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(subviews(of:))
}
