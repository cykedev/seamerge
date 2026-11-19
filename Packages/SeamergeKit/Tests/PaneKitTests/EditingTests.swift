import AppKit
import PaneKit
import Testing
import TextBasics

/// Checks the single way into an editable pane's text: every edit asks the editing delegate
/// first, the pane carries out exactly what the delegate answers, and a change that bypasses the
/// delegate is reported.
@MainActor
@Suite struct EditingTests {
  /// The ways of editing text that the text view offers, each with what it should announce.
  enum Input: CaseIterable, CustomTestStringConvertible {
    case typing
    case deletingBackward
    case deletingForward
    case deletingAWordBackward
    case insertingANewline
    case insertingATab
    case pasting
    case deletingTheSelection
    case transposing
    case uppercasing
    case yanking
    case deadKey
    case inputMethodThatUnmarks

    var testDescription: String { "\(self)" }

    /// The text that every input starts from.
    static let text = "alpha beta\ngamma delta"

    /// The selection that the input starts from.
    var selection: NSRange {
      switch self {
      case .pasting: NSRange(location: 0, length: 5)
      case .deletingTheSelection: NSRange(location: 0, length: 6)
      case .uppercasing: NSRange(location: 0, length: 5)
      case .deletingAWordBackward: NSRange(location: 10, length: 0)
      case .transposing: NSRange(location: 2, length: 0)
      case .yanking: NSRange(location: 6, length: 0)
      default: NSRange(location: 5, length: 0)
      }
    }

    /// The edits that the input announces, in order.
    var edits: [PaneEdit] {
      switch self {
      case .typing: [PaneEdit(range: 5..<5, text: "X")]
      case .deletingBackward: [PaneEdit(range: 4..<5, text: "")]
      case .deletingForward: [PaneEdit(range: 5..<6, text: "")]
      case .deletingAWordBackward: [PaneEdit(range: 6..<10, text: "")]
      case .insertingANewline: [PaneEdit(range: 5..<5, text: "\n")]
      case .insertingATab: [PaneEdit(range: 5..<5, text: "\t")]
      case .pasting: [PaneEdit(range: 0..<5, text: "omega")]
      case .deletingTheSelection: [PaneEdit(range: 0..<6, text: "")]
      case .transposing: [PaneEdit(range: 1..<3, text: "pl")]
      case .uppercasing: [PaneEdit(range: 0..<5, text: "ALPHA")]
      case .yanking: [PaneEdit(range: 6..<10, text: ""), PaneEdit(range: 0..<0, text: "beta")]
      case .deadKey: [PaneEdit(range: 5..<5, text: "´"), PaneEdit(range: 5..<6, text: "é")]
      case .inputMethodThatUnmarks:
        [
          PaneEdit(range: 5..<5, text: "´"), PaneEdit(range: 5..<6, text: ""),
          PaneEdit(range: 5..<5, text: "´"),
        ]
      }
    }

    /// Makes the input in `textView`.
    @MainActor
    func perform(in textView: NSTextView) {
      let noReplacement = NSRange(location: NSNotFound, length: 0)
      switch self {
      case .typing: textView.insertText("X", replacementRange: noReplacement)
      case .deletingBackward: textView.deleteBackward(nil)
      case .deletingForward: textView.deleteForward(nil)
      case .deletingAWordBackward: textView.deleteWordBackward(nil)
      case .insertingANewline: textView.insertNewline(nil)
      case .insertingATab: textView.insertTab(nil)
      case .pasting:
        let pasteboard = NSPasteboard(
          name: NSPasteboard.Name("Seamerge.Tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("omega", forType: .string)
        textView.readSelection(from: pasteboard)
      case .deletingTheSelection: textView.delete(nil)
      case .transposing: textView.transpose(nil)
      case .uppercasing: textView.uppercaseWord(nil)
      case .yanking:
        textView.deleteToEndOfLine(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.yank(nil)
      case .deadKey:
        textView.setMarkedText(
          "´", selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
        textView.insertText("é", replacementRange: noReplacement)
      case .inputMethodThatUnmarks:
        textView.setMarkedText(
          "´", selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
        textView.unmarkText()
      }
    }
  }

  @Test(arguments: Input.allCases)
  func everyInputAsksTheDelegateBeforeItChangesTheText(input: Input) throws {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(input.selection)
    var text = Input.text as NSString
    var replacedTexts: [String] = []
    for edit in input.edits {
      replacedTexts.append(text.substring(with: NSRange(edit.range)))
      text = text.replacingCharacters(in: NSRange(edit.range), with: edit.text) as NSString
    }
    input.perform(in: textView)
    #expect(recorder.asked == input.edits)
    #expect(recorder.carriedOut.flatMap(\.edits) == input.edits)
    #expect(recorder.carriedOut.flatMap(\.replacedTexts) == replacedTexts)
    #expect(recorder.unannounced.isEmpty)
    #expect(textView.string == text as String)
  }

  @Test func contentWithTheTextFromBeforeAnEditReplacesTheEditedText() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    pane.documentView.setSelectedRange(NSRange(location: 5, length: 0))
    pane.documentView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(recorder.carriedOut.count == 1)

    pane.content = Self.content(Input.text)

    #expect(pane.documentView.string == Input.text)
  }

  @Test func editThatTheDelegateRefusesLeavesTheTextAlone() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    recorder.answer = { _ in [] }
    pane.documentView.setSelectedRange(NSRange(location: 5, length: 0))
    pane.documentView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
    pane.documentView.deleteBackward(nil)
    #expect(recorder.asked.count == 2)
    #expect(recorder.carriedOut.isEmpty)
    #expect(pane.documentView.string == Input.text)
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func answerThatDiffersFromTheEditIsCarriedOutExactly() {
    let (pane, window, recorder) = Self.editablePane(text: "first\nPREVIEW\nlast")
    defer { window.close() }
    // Typing over a selection from "st" in the first line to "la" in the last, around the line
    // in between.
    recorder.answerAround([6..<14])
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 3, length: 13))
    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    let expected = [PaneEdit(range: 14..<16, text: ""), PaneEdit(range: 3..<6, text: "x")]
    #expect(recorder.asked == [PaneEdit(range: 3..<16, text: "x")])
    #expect(recorder.carriedOut.map(\.edits) == [expected])
    #expect(recorder.carriedOut.map(\.replacedTexts) == [["la", "st\n"]])
    #expect(textView.string == "firxPREVIEW\nst")
    #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func editOfSeveralSelectionsAsksForEachOfThemFromTheLast() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let textView = pane.documentView
    let ranges = [NSRange(location: 0, length: 1), NSRange(location: 6, length: 1)]
    #expect(
      !textView.shouldChangeText(
        inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: ["A", "B"]))
    #expect(
      recorder.asked == [PaneEdit(range: 6..<7, text: "B"), PaneEdit(range: 0..<1, text: "A")])
    #expect(textView.string == "Alpha Beta\ngamma delta")
    // Each answer is reported before the next question, all within the action.
    #expect(
      recorder.carriedOut.map(\.edits) == [
        [PaneEdit(range: 6..<7, text: "B")], [PaneEdit(range: 0..<1, text: "A")],
      ])
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func singleEditThatDiffersFromTheEditIsCarriedOutInsteadOfIt() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    // The delegate moves an insertion to the end of the line, as it moves one out of a preview.
    let moved = PaneEdit(range: 10..<10, text: "X")
    recorder.answer = { _ in [moved] }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string == "alpha betaX\ngamma delta")
    #expect(textView.selectedRange() == NSRange(location: 11, length: 0))
    #expect(recorder.carriedOut.map(\.edits) == [[moved]])
    #expect(recorder.carriedOut.map(\.replacedTexts) == [[""]])
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func announcedEditThatNeverCameDoesNotMakeTheNextChangeUnannounced() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let textView = pane.documentView
    #expect(
      textView.shouldChangeText(
        inRanges: [NSValue(range: NSRange(location: 0, length: 1))], replacementStrings: ["Q"]))
    pane.carryOut([PaneEdit(range: 11..<16, text: "GAMMA")])
    #expect(textView.string == "alpha beta\nGAMMA delta")
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func newBlocksKeepTextSelectionAndRowsAndDrawTheirRowsAgain() throws {
    let (pane, window, recorder) = Self.editablePane(
      text: "zero\none\ntwo\nthree", blocks: [PaneBlock(rows: 1..<2, style: .tinted(.a))])
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 6, length: 2))
    window.makeFirstResponder(nil)
    let rowHeight = pane.theme.rowHeight
    let point = CGPoint(x: pane.bounds.width - 10, y: 2.5 * rowHeight)
    let before = try Rendering.color(in: try Rendering.bitmap(of: pane), at: point)
    pane.setBlocks(
      [PaneBlock(rows: 1..<2, style: .tinted(.a)), PaneBlock(rows: 2..<3, style: .handwritten)],
      previews: [], rowTints: [:])
    let after = try Rendering.color(in: try Rendering.bitmap(of: pane), at: point)
    #expect(pane.content.blocks.count == 2)
    #expect(pane.content.text == "zero\none\ntwo\nthree")
    #expect(textView.selectedRange() == NSRange(location: 6, length: 2))
    #expect(after.brightnessComponent < before.brightnessComponent - 0.02)
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func rowTintsMoveWithTheTextAndTheOwnerSetsThemAnew() throws {
    let (pane, window, recorder) = Self.editablePane(text: "zero\none\ntwo\nthree")
    defer { window.close() }
    pane.setBlocks([], previews: [], rowTints: [1: .handwritten, 3: .handwritten])
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.insertText("new\n", replacementRange: textView.selectedRange())

    // The rewritten row drops out; the rows after it move down with the text.
    #expect(pane.content.rowTints == [2: .handwritten, 4: .handwritten])
    let rowHeight = pane.theme.rowHeight
    let point = CGPoint(x: pane.bounds.width - 10, y: 0.5 * rowHeight)
    let before = try Rendering.color(in: try Rendering.bitmap(of: pane), at: point)
    pane.setBlocks(
      [], previews: [], rowTints: [0: .handwritten, 2: .handwritten, 4: .handwritten])
    let after = try Rendering.color(in: try Rendering.bitmap(of: pane), at: point)
    #expect(pane.content.rowTints == [0: .handwritten, 2: .handwritten, 4: .handwritten])
    #expect(after.brightnessComponent < before.brightnessComponent - 0.02)
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func typingInALongTextIsMatchedAlthoughTheWholeParagraphIsReportedAsEdited() {
    // In a long text, the text storage fixes the attributes of the whole paragraph along with a
    // change and reports all of it as edited.
    let lines = (0..<20_000).map { "    let value\($0) = compute(\($0)) // comment" }
    let (pane, window, recorder) = Self.editablePane(text: lines.joined(separator: "\n"))
    defer { window.close() }
    let textView = pane.documentView
    let offset = (lines[..<10_000].reduce(0) { $0 + $1.utf16.count + 1 }) + 8
    textView.setSelectedRange(NSRange(location: offset, length: 0))
    for _ in 0..<3 {
      textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    #expect(recorder.carriedOut.count == 3)
    #expect(recorder.unannounced.isEmpty)
    #expect(pane.content.lineNumbers.count == 20_000)
  }

  @Test func changeThatBypassesTheDelegateIsReported() throws {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let textView = pane.documentView
    textView.replaceCharacters(in: NSRange(location: 0, length: 5), with: "omega")
    let textStorage = try #require(textView.textStorage)
    textStorage.replaceCharacters(in: NSRange(location: 11, length: 0), with: "new\n")
    #expect(recorder.asked.isEmpty)
    #expect(
      recorder.unannounced == [
        PaneEdit(range: 0..<5, text: "omega"), PaneEdit(range: 11..<11, text: "new\n"),
      ])
    // The pane keeps its rows in step with the text all the same.
    #expect(pane.content.lineNumbers == [0, 1, 2])
    #expect(pane.content.text == "omega beta\nnew\ngamma delta")
  }

  @Test func carryingOutEditsReplacesTheTextWithoutAskingTheDelegate() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let replaced = pane.carryOut([
      PaneEdit(range: 11..<22, text: "theta"), PaneEdit(range: 0..<0, text: ">"),
    ])
    #expect(replaced == ["gamma delta", ""])
    #expect(pane.documentView.string == ">alpha beta\ntheta")
    #expect(recorder.asked.isEmpty)
    #expect(recorder.carriedOut.isEmpty)
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func paneWithoutEditingDelegateCannotBeEdited() {
    let pane = PaneView()
    pane.content = Self.content(Input.text)
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 120), isKey: true)
    defer { window.close() }
    window.makeFirstResponder(pane.documentView)
    #expect(!pane.documentView.isEditable)
    pane.documentView.insertText("X", replacementRange: NSRange(location: 0, length: 0))
    #expect(pane.documentView.string == Input.text)
  }

  @Test func textViewKeepsNoUndoOfItsOwn() {
    let (pane, window, recorder) = Self.editablePane(text: Input.text)
    defer { window.close() }
    let textView = pane.documentView
    #expect(!textView.allowsUndo)
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(recorder.carriedOut.count == 1)
    #expect(textView.undoManager?.canUndo != true)
  }

  @Test func rowsBlocksAndLineNumbersFollowTheText() {
    let (pane, window, recorder) = Self.editablePane(
      text: "zero\none\ntwo\nthree",
      blocks: [
        PaneBlock(rows: 1..<2, style: .tinted(.a)), PaneBlock(rows: 3..<4, style: .tinted(.b)),
      ])
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 7, length: 0))
    textView.insertNewline(nil)
    #expect(pane.content.lineNumbers == [0, 1, 2, 3, 4])
    #expect(pane.content.blocks.map(\.rows) == [1..<3, 4..<5])
    #expect(pane.content.lineEndings == [.lf, .lf, .lf, .lf, nil])
    // Deleting from the end of row 1 into row 3 joins them; the joined row goes to the block in
    // which the deletion starts.
    textView.setSelectedRange(NSRange(location: 7, length: 4))
    textView.delete(nil)
    #expect(pane.content.text == "zero\nonwo\nthree")
    #expect(pane.content.lineNumbers == [0, 1, 2])
    #expect(pane.content.blocks.map(\.rows) == [1..<2, 2..<3])
    #expect(pane.hit(at: CGPoint(x: 100, y: 2.5 * pane.theme.rowHeight)).row == 2)
    #expect(recorder.unannounced.isEmpty)
  }

  @Test func rowOfAnOffsetFollowsTheText() {
    let (pane, window, _) = Self.editablePane(text: "zero\none\ntwo\n")
    defer { window.close() }
    // A line feed belongs to the row it ends; the end of a text that ends with a line feed lies
    // in the empty last row.
    #expect([0, 4, 5, 8, 9, 12, 13].map(pane.row(containingOffset:)) == [0, 0, 1, 1, 2, 2, 3])
    pane.carryOut([PaneEdit(range: 2..<2, text: "\n")])
    #expect(pane.documentView.string == "ze\nro\none\ntwo\n")
    #expect([2, 3, 6, 14].map(pane.row(containingOffset:)) == [0, 1, 2, 4])
    pane.carryOut([PaneEdit(range: 0..<10, text: "")])
    #expect(pane.documentView.string == "two\n")
    #expect([0, 3, 4].map(pane.row(containingOffset:)) == [0, 0, 1])
  }

  @Test func linesTypedInAFileWithCRLFEndLikeTheLineTheyWereTypedIn() {
    let pane = PaneView()
    pane.content = PaneContent(
      text: "one\ntwo", lineNumbers: [0, 1], lineEndings: [.crlf, nil])
    pane.showsInvisibles = true
    let recorder = EditRecorder()
    pane.editingDelegate = recorder
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 120), isKey: true)
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.insertNewline(nil)
    #expect(pane.content.lineEndings == [.crlf, .crlf, nil])
    // At the end of the text, the last line has no ending; the new line takes the one before.
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.insertNewline(nil)
    #expect(
      pane.content.lineEndings == [
        .crlf, .crlf, .crlf, nil,
      ])
    #expect(recorder.carriedOut.count == 2)
  }

  @Test func lineTypedIntoATextOfOneLineEndsWithALineFeed() {
    let (pane, window, recorder) = Self.editablePane(text: "only")
    defer { window.close() }
    pane.documentView.setSelectedRange(NSRange(location: 4, length: 0))
    pane.documentView.insertNewline(nil)
    #expect(pane.content.lineEndings == [.lf, nil])
    #expect(recorder.carriedOut.count == 1)
  }

  @Test func contentWithTheSameTextKeepsSelectionAndScrollPosition() {
    let lines = (0..<60).map { "line \($0)" }
    let (pane, window, _) = Self.editablePane(text: lines.joined(separator: "\n"))
    defer { window.close() }
    let textView = pane.documentView
    textView.scroll(CGPoint(x: 0, y: 10 * pane.theme.rowHeight))
    textView.setSelectedRange(NSRange(location: 200, length: 7))
    var content = pane.content
    content.blocks = [PaneBlock(rows: 20..<22, style: .handwritten)]
    pane.setContent(content, collapsedRuns: [])
    #expect(textView.selectedRange() == NSRange(location: 200, length: 7))
    #expect(textView.visibleRect.minY == 10 * pane.theme.rowHeight)
    #expect(pane.content.blocks == content.blocks)
  }

  /// An editable pane with `text`, one line per row, in a key window with the text focused.
  static func editablePane(
    text: String, blocks: [PaneBlock] = [], previews: [PanePreview] = [],
    size: CGSize = CGSize(width: 400, height: 200)
  ) -> (PaneView, NSWindow, EditRecorder) {
    let pane = PaneView()
    var content = Self.content(text, blocks: blocks)
    content.previews = previews
    pane.content = content
    let recorder = EditRecorder()
    pane.editingDelegate = recorder
    let window = Rendering.host(pane, size: size, isKey: true)
    window.makeFirstResponder(pane.documentView)
    return (pane, window, recorder)
  }

  /// The content of `text` with one line per row and no fillers.
  static func content(_ text: String, blocks: [PaneBlock] = []) -> PaneContent {
    let rowCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return PaneContent(
      text: text, lineNumbers: (0..<rowCount).map { Int32($0) }, blocks: blocks)
  }
}
