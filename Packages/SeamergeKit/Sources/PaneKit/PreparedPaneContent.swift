import Foundation

/// The content of a pane with what showing it takes worked out beforehand, away from the main
/// actor: the rows of its text, and the text as a text view stores it.
///
/// Showing prepared content leaves the main actor only putting it in place, which for a text of
/// several megabytes is a matter of a millisecond rather than of tens of them.
public struct PreparedPaneContent: Sendable {
  /// What the pane shows.
  public let content: PaneContent

  /// The rows of the text with tabs of `tabWidth` columns.
  let grid: RowGrid

  /// The width of a tab in columns that the rows were found with.
  let tabWidth: Int

  /// The text of the content, stored in UTF-16 as a text view stores it.
  let storedText: String

  /// Prepares `content` for a pane whose tabs are `tabWidth` columns wide; best done away from
  /// the main actor, since it takes time in proportion to the text.
  public init(preparing content: PaneContent, tabWidth: Int) {
    self.content = content
    self.tabWidth = tabWidth
    let units = Array(content.text.utf16)
    // A string that keeps the UTF-16 storage it is made from hands it to the text view as it is.
    storedText = NSString(characters: units, length: units.count) as String
    grid = RowGrid(text: content.text, tabWidth: tabWidth)
  }
}
