import AppKit
import PaneKit
import Testing

/// Checks what a change of the text's width lays out again: the fragments in view, whose rendering
/// surfaces take the new width, and not the whole text, which TextKit would lay out from the top
/// as often as a line typed at the right edge widens the text.
@MainActor
@Suite struct WideningTests {
  @Test func widerTextLaysOutTheFragmentsInViewAgainAndKeepsTheOthers() throws {
    let pane = PaneView()
    let lines = (0..<200).map { "line \($0)" }
    pane.content = PaneContent(
      text: lines.joined(separator: "\n"), lineNumbers: lines.indices.map { Int32($0) })
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200))
    defer { window.close() }
    pane.displayIfNeeded()
    let textView = pane.documentView
    let layoutManager = try #require(textView.textLayoutManager)
    layoutManager.ensureLayout(for: layoutManager.documentRange)
    func fragment(atRow row: Int) throws -> NSTextLayoutFragment {
      let offset = lines[..<row].reduce(0) { $0 + $1.utf16.count + 1 }
      let location = try #require(
        layoutManager.location(layoutManager.documentRange.location, offsetBy: offset))
      return try #require(layoutManager.textLayoutFragment(for: location))
    }
    let inView = try fragment(atRow: 2)
    let outOfView = try fragment(atRow: 150)
    #expect(inView.state == .layoutAvailable)
    #expect(outOfView.state == .layoutAvailable)
    textView.setFrameSize(CGSize(width: textView.frame.width + 100, height: textView.frame.height))
    #expect(inView.state != .layoutAvailable)
    #expect(outOfView.state == .layoutAvailable)
  }
}
