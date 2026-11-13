import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// Typing in the result window: every row of the attribution of edits to segments, through the
/// keys and Paste of the text view.
@MainActor
@Suite struct ResultTypingTests {
  @Test func resultIsEditableAndShowsItsTextAsLoaded() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    #expect(try controller.mergeResult.documentView.isEditable)
    #expect(try controller.presentation.mergeResult.text == EditingFixture.loadedText)
    try controller.checkResultIsShownAsModelled()
  }

  @Test(arguments: Input.allCases)
  func editWithinASegmentChangesItsLengthAndMakesItEdited(input: Input) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    // Within A1, after A; deleting backward takes the A.
    try controller.type("x", over: 4..<4, with: input)

    let segments = try controller.segmentTexts
    #expect(segments[1] == (input == .deleteBackward ? "1\n" : "Ax1\n"))
    #expect(segments[0] == "u0\n" && segments[2] == "u2\n")
    #expect(try controller.segmentStates[1] == .edited)
    try controller.checkResultIsShownAsModelled()
  }

  @Test(arguments: Input.allCases)
  func insertionOnABoundaryGoesToTheLineTypedOn(input: Input) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    // At the start of A1, the boundary of segments 0 and 1; deleting backward takes the line
    // feed before it, which belongs to segment 0.
    try controller.type("x", over: 3..<3, with: input)

    let segments = try controller.segmentTexts
    let states = try controller.segmentStates
    if input == .deleteBackward {
      #expect(segments[0] == "u0" && segments[1] == "A1\n")
      #expect(states[0] == .edited && states[1] == .auto)
    } else {
      #expect(segments[0] == "u0\n" && segments[1] == "xA1\n")
      #expect(states[0] == .untouched && states[1] == .edited)
    }
    try controller.checkResultIsShownAsModelled()
  }

  @Test(arguments: [Input.insertText, .paste])
  func insertionAtTheEndGoesToTheLastSegment(input: Input) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let end = try controller.mergeResult.content.text.utf16.count

    try controller.type("\nu9", over: end..<end, with: input)

    #expect(try controller.segmentTexts[8] == "u8\nu9\n")
    #expect(try controller.presentation.mergeResult.text.hasSuffix("u8\nu9\n"))
    try controller.checkResultIsShownAsModelled()
  }

  @Test(arguments: Input.allCases)
  func editAcrossSegmentsGivesTheTextToTheFirstAndEmptiesThoseBetween(input: Input) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    // From after u in u4 to after B5's line into u6: segment 4 keeps its start, 5 empties, 6
    // keeps its end.
    try controller.type("x", over: 16..<22, with: input)

    let segments = try controller.segmentTexts
    let typed = input == .deleteBackward ? "" : "x"
    #expect(segments[4] == "u\(typed)" && segments[5].isEmpty && segments[6] == "6\n")
    #expect(try controller.segmentStates[4...6].allSatisfy { $0 == .edited })
    try controller.checkResultIsShownAsModelled()
  }

  @Test(arguments: Input.allCases)
  func editAcrossAPreviewIsCarriedOutAroundIt(input: Input) async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    // From after A in A1 over u2 and the preview of the conflict into u4.
    try controller.type("x", over: 4..<16, with: input)

    let segments = try controller.segmentTexts
    let typed = input == .deleteBackward ? "" : "x"
    #expect(segments[1] == "A\(typed)" && segments[2].isEmpty)
    #expect(segments[3] == "A3\nB3\n")
    #expect(segments[4] == "4\n")
    let states = try controller.segmentStates
    #expect(states[3] == .open && states[1] == .edited && states[4] == .edited)
    try controller.checkResultIsShownAsModelled()
  }

  @Test func previewSurvivesSelectingAllAndDeleting() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let textView = try controller.resultTextView

    textView.selectAll(nil)
    textView.deleteBackward(nil)

    let segments = try controller.segmentTexts
    #expect(segments[3] == "A3\nB3\n")
    #expect(segments[7] == "\(EditingFixture.removalNote)\nY7\n")
    #expect(try controller.segmentStates.filter { $0 == .open }.count == 2)
    try controller.checkResultIsShownAsModelled()

    // Typing is never refused while a segment takes text.
    textView.insertText("new", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(try controller.presentation.mergeResult.text.contains("new"))
    try controller.checkResultIsShownAsModelled()
  }

  @Test func typedLineBreakTakesTheLineEndingOfItsLine() async throws {
    let session = try await SampleMerges.merge(
      base: "one\r\ntwo\r\n", a: "one\r\nTWO\r\n", b: "one\r\ntwo\r\n")
    let controller = try Windows.controller(for: session)

    try controller.type("\n", over: 1..<1, with: .insertText)

    #expect(try controller.presentation.mergeResult.text == "o\r\nne\r\nTWO\r\n")
    try controller.checkResultIsShownAsModelled()
  }

  @Test func caretAfterTheLastLineTypesBeforeTheFinalLineBreak() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let textView = try controller.resultTextView
    let end = try controller.mergeResult.content.text.utf16.count

    textView.setSelectedRange(NSRange(location: end, length: 0))
    textView.insertNewline(nil)
    textView.insertText("u9", replacementRange: NSRange(location: NSNotFound, length: 0))

    #expect(try controller.presentation.mergeResult.text.hasSuffix("u8\nu9\n"))
    #expect(try controller.mergeResult.content.text.hasSuffix("u8\nu9"))
    try controller.checkResultIsShownAsModelled()
  }

  @Test func blocksAfterCharactersBeyondTheBasicPlaneLieOnTheirRows() async throws {
    let session = try await SampleMerges.merge(
      base: "😀 one\nx\n", a: "😀 one\ny\n", b: "😀 one\nx\n")
    let controller = try Windows.controller(for: session)

    try controller.type("😀", over: 0..<0, with: .insertText)

    #expect(try controller.mergeResult.content.blocks.map(\.rows) == [1..<2])
    #expect(try controller.segmentTexts == ["😀😀 one\n", "y\n"])
    try controller.checkResultIsShownAsModelled()
  }

  @Test func typingMakesTheBlockOfTheInsertionPointCurrent() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let textView = try controller.resultTextView
    // Within A1; then another block becomes current, as a jump of the panes above makes it.
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    controller.presentation.setCurrentBlock(2)

    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))

    #expect(controller.presentation.currentBlock == 0)
  }

  @Test func typingInAnUnchangedBlockLeavesItsOtherLinesUntinted() async throws {
    let session = try await SampleMerges.merge(
      base: "u0\nu1\nx\n", a: "u0\nu1\nA\n", b: "u0\nu1\nB\n")
    let controller = try Windows.controller(for: session)

    try controller.type("z", over: 1..<1, with: .insertText)

    #expect(try controller.mergeResult.content.rowTints == [0: .handwritten])
  }

  /// Lines of an edited block that keep their text keep the tint of the block before typing: of
  /// the side that changed it, or of both where both made the same change.
  @Test func linesOfAnEditedBlockThatKeepTheirTextKeepTheTintOfTheBlock() async throws {
    let session = try await SampleMerges.merge(
      base: "u\nx0\nx1\nu\ny0\ny1\nu\n", a: "u\nX0\nX1\nu\nY0\nY1\nu\n",
      b: "u\nx0\nx1\nu\nY0\nY1\nu\n")
    try #require(session.blocks.map(\.kind).contains(.changedInBoth))
    let controller = try Windows.controller(for: session)

    // At the start of X0 and of Y0.
    try controller.type("!", over: 2..<2, with: .insertText)
    try controller.type("!", over: 13..<13, with: .insertText)

    let tints = try controller.mergeResult.content.rowTints
    #expect(tints == [1: .handwritten, 2: .tinted(.a), 4: .handwritten, 5: .combined])
    try controller.checkResultIsShownAsModelled()
  }

  @Test func handTypedLinesAreTintedGrayAndOnlyThose() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())

    try controller.type("\nnew", over: 5..<5, with: .insertText)

    let pane = try controller.mergeResult
    #expect(pane.content.rowTints == [1: .tinted(.a), 2: .handwritten])
    #expect(pane.content.blocks[0].style == .tinted(.a))
    try controller.checkResultIsShownAsModelled()
  }

  /// Changes of the text that bypass the plans, which only a bug causes, are each attributed as
  /// typing would be, also two before the result is shown again.
  @Test func changesThatNobodyAnnouncedAreTakenOverOneAfterTheOther() async throws {
    let controller = try Windows.controller(for: try await EditingFixture.nineBlocks())
    let textStorage = try #require(try controller.mergeResult.documentView.textStorage)

    textStorage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "x")
    textStorage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "y")
    await Task.yield()

    let segments = try controller.segmentTexts
    #expect(segments[0] == "uy0\n" && segments[1] == "Ax1\n")
    try controller.checkResultIsShownAsModelled()
  }
}
