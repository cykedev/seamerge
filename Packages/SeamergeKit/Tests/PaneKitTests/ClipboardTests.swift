import AppKit
import PaneKit
import Testing

/// Checks that copying, dragging and services take only the lines of the file, never filler
/// rows or invisible characters.
@MainActor
@Suite struct ClipboardTests {
  @Test(arguments: [
    (NSRange(location: 0, length: 14), "first\nsecond"),
    (NSRange(location: 2, length: 10), "rst\nseco"),
    (NSRange(location: 6, length: 8), "second"),
    (NSRange(location: 0, length: 7), "first\n"),
    (NSRange(location: 6, length: 1), ""),
    (NSRange(location: 10, length: 12), "cond\nthird\n"),
  ])
  func copyingAcrossFillerRowsGivesOnlyTheLinesOfTheFile(selection: NSRange, copied: String)
    throws
  {
    let pane = Self.pane()
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200))
    defer { window.close() }
    pane.documentView.setSelectedRange(selection)
    let result = try Self.copy(from: pane)
    #expect(result == copied)
  }

  @Test func severalSelectionsAreCopiedOneLineEach() throws {
    let pane = Self.pane()
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200))
    defer { window.close() }
    pane.documentView.setSelectedRanges(
      [
        NSValue(range: NSRange(location: 0, length: 5)),
        NSValue(range: NSRange(location: 8, length: 6)),
      ],
      affinity: .downstream, stillSelecting: false)
    let copied = try Self.copy(from: pane)
    #expect(copied == "first\nsecond")
  }

  @Test func invisibleCharactersAreNeverCopied() throws {
    let pane = PaneView()
    pane.content = PaneContent(
      text: "a b\tc\nd", lineNumbers: [0, 1],
      lineEndings: [.carriageReturnLineFeed, .none])
    pane.showsInvisibles = true
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 100))
    defer { window.close() }
    pane.documentView.selectAll(nil)
    let copied = try Self.copy(from: pane)
    #expect(copied == "a b\tc\nd")
  }

  /// "first" at 0, filler rows at 6 and 7, "second" at 8, a filler row at 15, "third" at 16, and
  /// an empty filler row at 22, the end.
  private static func pane() -> PaneView {
    let pane = PaneView()
    pane.content = PaneContent(
      text: "first\n\n\nsecond\n\nthird\n", lineNumbers: [0, -1, -1, 1, -1, 2, -1])
    return pane
  }

  /// Copies the selection of `pane` to a pasteboard of its own, never the user's clipboard.
  private static func copy(from pane: PaneView) throws -> String? {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("Seamerge.Tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let textView = pane.documentView
    try #require(textView.writablePasteboardTypes == [.string])
    try #require(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
    return pasteboard.string(forType: .string)
  }
}
