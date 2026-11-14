import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The text of the panes sits in the middle of its rows, and in the window as well, the input
/// method and VoiceOver find it there: the rectangles they ask for lie in the middle of the row
/// of the characters.
@MainActor
@Suite struct TextGeometryTests {
  @Test func inputMethodAndVoiceOverFindTheTextInTheMiddleOfItsRow() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let window = try #require(controller.window)
    for pane in Windows.panes(of: controller) {
      let textView = pane.documentView
      let row = 4
      let range = NSRange(location: pane.content.offset(ofRow: row), length: 4)
      var actualRange = NSRange()
      let rects = [
        textView.firstRect(forCharacterRange: range, actualRange: &actualRange),
        textView.accessibilityFrame(for: range),
      ]
      let rowTop = pane.verticalSpan(ofRows: row..<row + 1).lowerBound
      let rowBottom = rowTop + pane.theme.rowHeight
      for onScreen in rects {
        let rect = textView.convert(window.convertFromScreen(onScreen), from: nil)
        #expect(rect.minY >= rowTop - 0.5 && rect.maxY <= rowBottom + 0.5)
        #expect(abs((rect.minY - rowTop) - (rowBottom - rect.maxY)) <= 1.5)
      }
    }
  }
}
