import AppKit
import PaneKit
import Testing

/// Checks the previews of conflicts in an editable pane: the insertion point never enters them,
/// copying leaves them out, typing goes around them, and they look quieter than text.
@MainActor
@Suite struct PreviewTests {
  /// A line, a preview of A's two lines and of B's line, and a line after them.
  static let text = "before\na one\na two\nb one\nafter"

  /// The preview of A's lines and of B's line, which follow each other.
  static let previews = [
    PanePreview(range: 7..<19, role: .a), PanePreview(range: 19..<25, role: .b),
  ]

  @Test func arrowKeysSkipThePreviewInTheDirectionTheyMove() {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.moveDown(nil)
    #expect(textView.selectedRange() == NSRange(location: 25, length: 0))
    textView.moveUp(nil)
    #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    textView.moveRight(nil)
    #expect(textView.selectedRange() == NSRange(location: 25, length: 0))
    textView.moveLeft(nil)
    #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    textView.moveToBeginningOfDocument(nil)
    textView.moveDown(nil)
    textView.moveDown(nil)
    #expect(textView.selectedRange() == NSRange(location: 30, length: 0))
  }

  @Test func clickOnThePreviewLeavesTheInsertionPointOutsideIt() {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    let rowHeight = pane.theme.rowHeight
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    // A click selects the place under the mouse while the button is down and once more when it
    // goes up; the mouse itself would hold the test run in its tracking loop.
    for row in 1..<4 {
      let index = textView.characterIndexForInsertion(
        at: CGPoint(x: 60, y: (CGFloat(row) + 0.5) * rowHeight))
      for stillSelecting in [true, false] {
        textView.setSelectedRanges(
          [NSValue(range: NSRange(location: index, length: 0))], affinity: .downstream,
          stillSelecting: stillSelecting)
        #expect(!Self.isWithinPreview(textView.selectedRange().location), "row \(row)")
      }
    }
  }

  @Test func selectAllNeverEndsWithinAPreview() {
    for previews in [Self.previews, [PanePreview(range: 0..<7, role: .a)]] {
      let (pane, window, _) = Self.pane(previews: previews)
      let textView = pane.documentView
      textView.selectAll(nil)
      let selection = textView.selectedRange()
      for end in [selection.location, selection.location + selection.length] {
        #expect(!previews.contains { $0.range.lowerBound < end && end < $0.range.upperBound })
      }
      window.close()
    }
  }

  @Test func selectionThatGrowsIntoThePreviewTakesInAllOfIt() {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.moveDownAndModifySelection(nil)
    #expect(textView.selectedRange() == NSRange(location: 2, length: 23))
    textView.moveUpAndModifySelection(nil)
    #expect(textView.selectedRange() == NSRange(location: 2, length: 5))
  }

  @Test func insertionPointAfterTextOnTheFirstRowOfAPreviewStaysThere() {
    // The line feed before the preview was deleted, so it starts in the middle of a row.
    let (pane, window, _) = Self.pane(
      text: "beforea one\nafter", previews: [PanePreview(range: 6..<12, role: .a)])
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 6, length: 0))
    #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    textView.moveRight(nil)
    #expect(textView.selectedRange() == NSRange(location: 12, length: 0))
    textView.moveLeft(nil)
    #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
  }

  @Test func copyingLeavesThePreviewsOut() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    pane.documentView.selectAll(nil)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("Seamerge.Tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try #require(pane.documentView.writeSelection(to: pasteboard, types: [.string]))
    #expect(pasteboard.string(forType: .string) == "before\nafter")
  }

  @Test func typingOverEverythingGoesAroundThePreviews() {
    let (pane, window, recorder) = Self.pane()
    defer { window.close() }
    recorder.answerAround(Self.previews.map(\.range))
    let textView = pane.documentView
    textView.selectAll(nil)
    textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string == "xa one\na two\nb one\n")
    #expect(pane.content.previews.map(\.range) == [1..<13, 13..<19])
    #expect(textView.selectedRange() == NSRange(location: 1, length: 0))
    #expect(recorder.unannounced.isEmpty)
  }

  @Test(arguments: [false, true])
  func previewIsDrawnQuieterThanTextInTheTintOfItsSide(isCurrent: Bool) throws {
    let (pane, window, _) = EditingTests.editablePane(
      text: Self.text, blocks: [PaneBlock(rows: 1..<4, style: .tinted(.conflict))],
      previews: Self.previews)
    defer { window.close() }
    // Drawing the current block anew must keep the preview's color.
    pane.currentBlock = isCurrent ? 0 : nil
    window.makeFirstResponder(nil)
    let bitmap = try Rendering.bitmap(of: pane)
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width
    let rowHeight = pane.theme.rowHeight
    func darkestInk(inRow row: Int) throws -> CGFloat {
      var darkest: CGFloat = 1
      for x in stride(from: textStart + 12, to: textStart + 60, by: 0.5) {
        for y in stride(
          from: CGFloat(row) * rowHeight + 2, to: CGFloat(row + 1) * rowHeight - 2, by: 0.5)
        {
          darkest = min(
            darkest, try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y)).brightnessComponent)
        }
      }
      return darkest
    }
    let text = try darkestInk(inRow: 0)
    for row in 1..<4 {
      #expect(try darkestInk(inRow: row) > text + 0.2, "row \(row)")
    }
    let fill = { (row: Int, role: ColorRole) throws -> (NSColor, NSColor) in
      let drawn = try Rendering.color(
        in: bitmap, at: CGPoint(x: pane.bounds.width - 20, y: (CGFloat(row) + 0.5) * rowHeight))
      let expected = Contrast.over(
        Contrast.resolve(
          pane.theme.rowFill(for: .tinted(role), isFiller: false, isCurrent: isCurrent),
          in: window.effectiveAppearance),
        Contrast.resolve(Theme.backgroundColor, in: window.effectiveAppearance) ?? .white)
      return (drawn, expected)
    }
    for (row, role) in [(1, ColorRole.a), (2, .a), (3, .b)] {
      let (drawn, expected) = try fill(row, role)
      #expect(abs(drawn.redComponent - expected.redComponent) < 0.02, "row \(row)")
      #expect(abs(drawn.blueComponent - expected.blueComponent) < 0.02, "row \(row)")
    }
  }

  @Test func textTypedNextToAPreviewHasTheColorOfText() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let textView = pane.documentView
    textView.setSelectedRange(NSRange(location: 25, length: 0))
    textView.insertText("new ", replacementRange: NSRange(location: NSNotFound, length: 0))
    let storage = try #require(textView.textStorage)
    let color = storage.attribute(.foregroundColor, at: 25, effectiveRange: nil) as? NSColor
    #expect(color == Theme.textColor)
  }

  @Test func previewThatTurnsIntoTextCrossFades() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let layer = try #require(pane.documentView.enclosingScrollView?.contentView.layer)
    #expect(Self.fade(on: layer) == nil)
    // Switching A on: A's lines become text, B's preview goes.
    pane.carryOut([PaneEdit(range: 7..<25, text: "a one\na two\n")])
    #expect(Self.fade(on: layer)?.duration == 0.15)
    layer.removeAllAnimations()
    // Resetting the block: the text of the preview comes back, then the content that names it
    // a preview.
    pane.carryOut([PaneEdit(range: 7..<19, text: "a one\na two\nb one\n")])
    #expect(Self.fade(on: layer) == nil)
    var content = pane.content
    content.previews = Self.previews
    pane.setContent(content, collapsedRuns: [])
    #expect(Self.fade(on: layer)?.duration == 0.15)
  }

  @Test func editThatTouchesNoPreviewDoesNotFade() throws {
    let (pane, window, _) = Self.pane()
    defer { window.close() }
    let layer = try #require(pane.documentView.enclosingScrollView?.contentView.layer)
    pane.carryOut([PaneEdit(range: 0..<6, text: "start")])
    #expect(Self.fade(on: layer) == nil)
  }

  /// The cross-fade that runs on `layer`, if any.
  private static func fade(on layer: CALayer) -> CATransition? {
    (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CATransition }.first
  }

  /// Whether a place at `offset` of the standard text lies within one of its previews.
  private static func isWithinPreview(_ offset: Int) -> Bool {
    7 <= offset && offset < 25
  }

  /// An editable pane with `text` and `previews`, focused in a key window.
  static func pane(
    text: String = PreviewTests.text, previews: [PanePreview] = PreviewTests.previews
  ) -> (PaneView, NSWindow, EditRecorder) {
    EditingTests.editablePane(text: text, previews: previews)
  }
}
