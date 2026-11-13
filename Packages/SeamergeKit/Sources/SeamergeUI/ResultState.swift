import MergeModel

/// The result of a merge as a window shows it: the document, its text, and how the lines of the
/// text lie on the row grid of the panes above.
struct ResultState {
  /// The result.
  let document: ResultDocument

  /// The text of the result, in the form of the file and in that of the result pane.
  let resultText: ResultText

  /// How the lines of the text lie on the row grid of the panes above.
  let scrollMap: ScrollMap

  /// The rows of the result pane: its text and where each row starts in it.
  let rows: ResultPaneContent.Rows

  /// The text of the result as the file has it, as long as the segments of the document
  /// together.
  var text: String { resultText.string }

  /// The result `document` with `resultText`.
  ///
  /// - Precondition: The text is as long as the segments of `document` together.
  init(document: ResultDocument, resultText: ResultText) {
    self.document = document
    self.resultText = resultText
    scrollMap = ScrollMap(document: document, text: resultText.string)
    rows = ResultPaneContent.rows(of: resultText.string)
  }

  /// The result `document` with `text`, as the file has it.
  ///
  /// - Precondition: `text` is as long as the segments of `document` together.
  init(document: ResultDocument, text: String) {
    self.init(document: document, resultText: ResultText(text))
  }

  /// The result of `session` as loaded: every conflict open, every other change taken as the
  /// merge takes it; the preview of a conflict shows the note of `removalNotes` in place of the
  /// lines of a side that removed them.
  init(session: Session, removalNotes: [Role: String]) {
    let document = ResultDocument(session: session, removalNotes: removalNotes)
    self.init(document: document, text: document.initialText)
  }

  /// The row of the grid at `line` of the result, counted from 0.
  func gridRow(ofLine line: Int) -> Int {
    Int(scrollMap.row(atResultLine: Double(line)).rounded(.down))
  }

  /// The row of the result pane in which `offset` of its text lies; the end of the text lies in
  /// the last row.
  func row(ofPaneOffset offset: Int) -> Int {
    rows.row(ofPaneOffset: offset)
  }

  /// The line of the result at `row` of the grid.
  func line(ofGridRow row: Int) -> Int {
    Int(scrollMap.resultLine(atRow: Double(row)))
  }
}
