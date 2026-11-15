import AppKit
import Testing

@testable import PaneKit

/// A line too long to show whole: the pane shows its first part and an ellipsis, while its text
/// keeps all of the line.
@MainActor
@Suite struct LongLineTests {
  /// A line of 30 000 characters whose cut falls into an emoji, between two short lines.
  private static let longLine =
    String(repeating: "a", count: PaneView.maximumShownLineLength - 1) + "😀"
    + String(repeating: "b", count: 10_000)
  private static let text = "first\n" + longLine + "\nlast"

  private static func pane(wrapsLines: Bool = false) -> PaneView {
    let pane = PaneView()
    pane.wrapsLines = wrapsLines
    pane.content = PaneContent(text: text, lineNumbers: [0, 1, 2])
    return pane
  }

  @Test func longLineShowsItsFirstPartAndAnEllipsisBeforeTheCharacterAtItsLimit() throws {
    let pane = Self.pane()
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 200))
    defer { window.close() }

    let lines = try #require(Self.fragment(ofRow: 1, in: pane.textView)).textLineFragments
    let shown = try #require(lines.first).attributedString.string

    #expect(shown == String(repeating: "a", count: PaneView.maximumShownLineLength - 1) + "…\n")
    #expect(pane.textView.string == Self.text)
    // The width allows for the emoji at the cut, which counts two columns.
    #expect(
      pane.textView.textWidth
        <= (CGFloat(PaneView.maximumShownLineLength + 2) * pane.theme.characterWidth
        + 2 * Theme.textInset).rounded(.up))
  }

  @Test func wrappedLongLineTakesTheScreenLinesOfItsShownPart() throws {
    let pane = Self.pane(wrapsLines: true)
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 2_000))
    defer { window.close() }
    let manager = try #require(pane.textView.textLayoutManager)
    manager.ensureLayout(for: manager.documentRange)

    let laidOut = try #require(Self.fragment(ofRow: 1, in: pane.textView)).textLineFragments.count
    let columns = Int(
      (pane.textView.bounds.width - 2 * Theme.textInset) / pane.theme.characterWidth)

    #expect(pane.displayRows.lines(ofRows: 1..<2).count == laidOut)
    // The whole line would take more lines than fit its characters into full lines.
    #expect(laidOut < (Self.longLine as NSString).length / columns)
  }

  @Test func copyingALongLineGivesAllOfIt() throws {
    let pane = Self.pane()
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 200))
    defer { window.close() }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }

    pane.textView.setSelectedRange(
      NSRange(location: 6, length: (Self.longLine as NSString).length))
    #expect(pane.textView.writeSelection(to: pasteboard, types: [.string]))

    #expect(pasteboard.string(forType: .string) == Self.longLine)
  }

  @Test func editableLongLineShowsWholeWhileTheInsertionPointIsInItAndCutAgainAfterwards()
    throws
  {
    let (pane, window, recorder) = EditingTests.editablePane(
      text: Self.text, size: CGSize(width: 600, height: 300))
    defer { window.close() }
    defer { withExtendedLifetime(recorder) {} }
    let textView = pane.textView
    let lineStart = 6
    let lineEnd = lineStart + (Self.longLine as NSString).length

    textView.setSelectedRange(NSRange(location: lineStart, length: 0))
    textView.moveToEndOfLine(nil)
    #expect(textView.selectedRange().location == lineEnd)
    textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(
      (textView.string as NSString).substring(with: NSRange(location: lineEnd, length: 2)) == "X\n")
    let shown = try #require(Self.fragment(ofRow: 1, in: textView)?.textLineFragments.first)
    #expect(shown.attributedString.string.hasSuffix("bX\n"))

    textView.setSelectedRange(NSRange(location: lineStart + 19_990, length: 0))
    for _ in 0..<15 {
      textView.moveRight(nil)
    }
    // Fifteen characters on, the emoji at the limit counting two code units.
    #expect(textView.selectedRange().location == lineStart + 20_006)

    textView.setSelectedRange(NSRange(location: lineEnd + 2, length: 0))
    let cut = try #require(Self.fragment(ofRow: 1, in: textView)?.textLineFragments.first)
    #expect(cut.attributedString.string.hasSuffix("…\n"))
  }

  @Test func longLineOfAPaneThatCannotBeEditedStaysCutUnderTheSelection() throws {
    let pane = Self.pane()
    let window = Rendering.host(pane, size: CGSize(width: 600, height: 200))
    defer { window.close() }

    pane.textView.setSelectedRange(NSRange(location: 6, length: 0))

    let shown = try #require(Self.fragment(ofRow: 1, in: pane.textView)?.textLineFragments.first)
    #expect(shown.attributedString.string.hasSuffix("…\n"))
  }

  private static func fragment(ofRow row: Int, in textView: PaneTextView) -> NSTextLayoutFragment? {
    guard let manager = textView.textLayoutManager else { return nil }
    let offset = textView.grid.offsets(ofRow: row).lowerBound
    guard let location = manager.location(manager.documentRange.location, offsetBy: offset)
    else { return nil }
    manager.ensureLayout(for: NSTextRange(location: location))
    return manager.textLayoutFragment(for: location)
  }
}
