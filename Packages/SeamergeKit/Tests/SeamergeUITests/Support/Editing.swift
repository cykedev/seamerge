import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// A merge of nine blocks for the tests of editing the result, one line per input each:
/// unchanged, changed in A, unchanged, a conflict, unchanged, changed in B, unchanged, a conflict
/// in which A removed the line and B changed it, unchanged.
enum EditingFixture {
  /// The merge.
  static func nineBlocks() async throws -> Session {
    let session = try await SampleMerges.merge(
      base: "u0\nx1\nu2\nx3\nu4\nx5\nu6\nx7\nu8\n",
      a: "u0\nA1\nu2\nA3\nu4\nx5\nu6\nu8\n",
      b: "u0\nx1\nu2\nB3\nu4\nB5\nu6\nY7\nu8\n")
    try #require(
      session.blocks.map(\.kind) == [
        .unchanged, .changedInA, .unchanged, .conflict, .unchanged, .changedInB, .unchanged,
        .conflict, .unchanged,
      ])
    return session
  }

  /// The note that the preview of block 7 shows for A.
  static let removalNote = "a.txt removed these lines"

  /// The text of the result after loading, as the file has it.
  static let loadedText = "u0\nA1\nu2\nA3\nB3\nu4\nB5\nu6\n\(removalNote)\nY7\nu8\n"
}

/// The ways the tests type in the result, each of which goes through the text view as the
/// user's keys do.
enum Input: String, CaseIterable, CustomTestStringConvertible {
  case insertText, deleteBackward, paste

  var testDescription: String { rawValue }
}

extension SessionWindowController {
  /// The text view of the result, with the focus, as in text mode.
  var resultTextView: NSTextView {
    get throws {
      let textView = try mergeResult.documentView
      if window?.firstResponder !== textView {
        enterTextMode()
      }
      return textView
    }
  }

  /// Selects `range` of the result pane's text and types `text` over it with `input`: inserts
  /// it, pastes it, or deletes backward, which takes no text.
  func type(_ text: String, over range: Range<Int>, with input: Input) throws {
    let textView = try resultTextView
    textView.setSelectedRange(NSRange(range))
    switch input {
    case .insertText:
      textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    case .deleteBackward:
      textView.deleteBackward(nil)
    case .paste:
      let pasteboard = NSPasteboard.withUniqueName()
      defer { pasteboard.releaseGlobally() }
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
      // Nothing to paste changes nothing.
      #expect(textView.readSelection(from: pasteboard) || text.isEmpty)
    }
  }

  /// The text of each segment of the result, as the file has it.
  var segmentTexts: [String] {
    get throws {
      let result = try presentation.mergeResult
      let units = Array(result.text.utf16)
      return result.document.session.blocks.map { block in
        String(decoding: units[result.document.range(of: block)], as: UTF16.self)
      }
    }
  }

  /// The state of each segment of the result.
  var segmentStates: [Segment.State] {
    get throws {
      let document = try presentation.mergeResult.document
      return document.session.blocks.map { document.segment(for: $0).state }
    }
  }

  /// Records an issue for each way in which the window does not show its result as the model
  /// has it: the text and line endings of the result pane, its blocks, previews and
  /// handwritten rows, the signs of the decision column, and the segments covering the text.
  func checkResultIsShownAsModelled(
    _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let result = try presentation.mergeResult
    let pane = try mergeResult
    let expected = ResultPaneContent(
      result: ResultState(document: result.document, text: result.text),
      changes: presentation.changes, headers: presentation.headers)
    let document = result.document
    let units = Array(result.text.utf16)
    #expect(pane.content.text == expected.content.text, comment, sourceLocation: sourceLocation)
    #expect(
      pane.content.lineEndings == expected.content.lineEndings, comment,
      sourceLocation: sourceLocation)
    #expect(pane.content.blocks == expected.content.blocks, comment, sourceLocation: sourceLocation)
    #expect(
      pane.content.previews == expected.content.previews, comment, sourceLocation: sourceLocation)
    #expect(
      pane.content.rowTints == expected.content.rowTints, comment,
      sourceLocation: sourceLocation)
    #expect(
      presentation.decisionColumn?.decisions == expected.decisions, comment,
      sourceLocation: sourceLocation)
    #expect(
      document.segments.reduce(0) { $0 + $1.length } == units.count, comment,
      sourceLocation: sourceLocation)
    var previewed = IndexSet()
    for block in document.session.blocks where document.segment(for: block).state == .open {
      let range = document.range(of: block)
      #expect(
        String(decoding: units[range], as: UTF16.self) == document.previewText(for: block),
        comment, sourceLocation: sourceLocation)
      previewed.insert(
        integersIn: result.resultText.paneOffset(
          ofFileOffset: range.lowerBound)..<result.resultText.paneOffset(
            ofFileOffset: range.upperBound))
    }
    // The previews of the pane cover exactly the segments of the open conflicts.
    var shown = IndexSet()
    for preview in pane.content.previews {
      shown.insert(integersIn: preview.range)
    }
    #expect(shown == previewed, comment, sourceLocation: sourceLocation)
  }
}
