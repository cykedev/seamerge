import MergeModel

/// The result of a merge as a window shows it: the document, its text, and how the lines of the
/// text lie on the row grid of the panes above.
struct ResultState {
  /// The result.
  let document: ResultDocument

  /// The text of the result, as long as the segments of the document together.
  let text: String

  /// How the lines of the text lie on the row grid of the panes above.
  let scrollMap: ScrollMap

  /// The result `document` with `text`.
  ///
  /// - Precondition: `text` is as long as the segments of `document` together.
  init(document: ResultDocument, text: String) {
    self.document = document
    self.text = text
    scrollMap = ScrollMap(document: document, text: text)
  }

  /// The result of `session` as loaded: every conflict open, every other change taken as the
  /// merge takes it.
  init(session: Session) {
    let document = ResultDocument(session: session)
    self.init(document: document, text: document.initialText)
  }

  /// The row of the grid at `line` of the result, counted from 0.
  func gridRow(ofLine line: Int) -> Int {
    Int(scrollMap.row(atResultLine: Double(line)).rounded(.down))
  }

  /// The line of the result at `row` of the grid.
  func line(ofGridRow row: Int) -> Int {
    Int(scrollMap.resultLine(atRow: Double(row)))
  }
}
