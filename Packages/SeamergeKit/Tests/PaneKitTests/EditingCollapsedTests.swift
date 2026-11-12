import AppKit
import PaneKit
import Testing

/// Checks that editing an editable pane never removes or changes rows behind a collapsed run
/// without the run being expanded first.
@MainActor
@Suite struct EditingCollapsedTests {
  @Test func typingOverASelectionThatTakesInHiddenRowsAsksToExpandTheirRunInstead() {
    let (pane, window, recorder, expansions) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.selectAll(nil)
    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string == Self.text)
    #expect(expansions.runs == [CollapsedRun(rows: 10..<30)])
    #expect(recorder.asked.isEmpty)
  }

  @Test func deletingTheLineFeedBeforeTheRowAfterABarAsksToExpandItsRun() {
    let (pane, window, recorder, expansions) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: Self.start(ofRow: 30), length: 0))
    textView.deleteBackward(nil)
    #expect(textView.string == Self.text)
    #expect(expansions.runs == [CollapsedRun(rows: 10..<30)])
    #expect(recorder.asked.isEmpty)
  }

  @Test func insertionAtTheEndOfTheTextIntoARunThatReachesTheLastRowAsksToExpandIt() {
    let (pane, window, recorder, expansions) = Self.pane()
    defer { window.close() }
    pane.collapsedRuns = [CollapsedRun(rows: 30..<40)]
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: Self.text.utf16.count, length: 0))
    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string == Self.text)
    #expect(expansions.runs.last == CollapsedRun(rows: 30..<40))
    #expect(pane.collapsedRuns == [CollapsedRun(rows: 30..<40)])
    #expect(recorder.asked.isEmpty)
  }

  @Test func arrowKeyThatMovesOntoABarAsksToExpandItsRun() {
    let (pane, window, _, expansions) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: Self.start(ofRow: 9), length: 0))
    textView.moveDown(nil)
    #expect(expansions.runs == [CollapsedRun(rows: 10..<30)])
  }

  @Test func typingRightBeforeAndAfterABarChangesOnlyVisibleRows() {
    let (pane, window, recorder, expansions) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    let noReplacement = NSRange(location: NSNotFound, length: 0)
    textView.setSelectedRange(NSRange(location: Self.start(ofRow: 30), length: 0))
    textView.insertText("after ", replacementRange: noReplacement)
    textView.setSelectedRange(NSRange(location: Self.start(ofRow: 10) - 1, length: 0))
    textView.insertText(" before", replacementRange: noReplacement)
    #expect(recorder.carriedOut.count == 2)
    #expect(expansions.runs.isEmpty)
    #expect(pane.collapsedRuns == [CollapsedRun(rows: 10..<30)])
  }

  @Test func linesAddedAboveABarMoveItsRunDown() {
    let (pane, window, recorder, _) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: Self.start(ofRow: 2), length: 0))
    textView.insertNewline(nil)
    textView.insertNewline(nil)
    #expect(recorder.carriedOut.count == 2)
    #expect(pane.collapsedRuns == [CollapsedRun(rows: 12..<32)])
    pane.layoutSubtreeIfNeeded()
    #expect(textView.frame.height == 23 * pane.theme.rowHeight)
  }

  /// Forty lines, `line 0` to `line 39`.
  static let text = (0..<40).map { "line \($0)" }.joined(separator: "\n")

  /// The offset where `row` of the standard text starts.
  static func start(ofRow row: Int) -> Int {
    (0..<row).reduce(0) { $0 + "line \($1)".utf16.count + 1 }
  }

  /// An editable pane with the standard text, rows 10 to 29 collapsed, with the delegates that
  /// record its edits and the runs it asks to expand, which the pane holds weakly.
  static func pane() -> (PaneView, NSWindow, EditRecorder, Expansions) {
    let (pane, window, recorder) = EditingTests.editablePane(
      text: text, size: CGSize(width: 400, height: 600))
    pane.collapsedRuns = [CollapsedRun(rows: 10..<30)]
    let expansions = Expansions()
    pane.delegate = expansions
    return (pane, window, recorder, expansions)
  }
}

/// Records the runs that a pane asks to expand.
@MainActor
final class Expansions: PaneViewDelegate {
  private(set) var runs: [CollapsedRun] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {}

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? { nil }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    runs.append(run)
  }

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {}
}
