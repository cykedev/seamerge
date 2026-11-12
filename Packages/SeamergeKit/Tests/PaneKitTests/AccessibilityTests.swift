import AppKit
import PaneKit
import Testing

/// Checks that VoiceOver finds every mark of the gutter, with a role, a name and its line.
@MainActor
@Suite struct AccessibilityTests {
  @Test func gutterNamesEveryVisibleMarkWithItsLine() throws {
    let provider = Removals()
    let pane = PaneView()
    pane.content = PaneContent(
      text: "let a = 1\nlet b = 2\n\n\nlet c = 3\nlet d = 4",
      lineNumbers: [0, 1, -1, -1, 2, 3],
      blocks: [
        PaneBlock(rows: 0..<1, style: .tinted(.a), marker: .changed),
        PaneBlock(rows: 2..<4, style: .tinted(.a), marker: .removed),
        PaneBlock(rows: 4..<5, style: .tinted(.a), marker: .added, conflict: .open),
      ],
      ignoredDifferenceRows: [5])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200))
    defer { window.close() }
    let gutter = try #require(
      pane.subviews.first { $0.accessibilityLabel() == "Change markers" })
    #expect(gutter.isAccessibilityElement())
    #expect(gutter.accessibilityRole() == .group)
    let marks = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    let described = marks.map {
      "\($0.accessibilityLabel() ?? ""), \($0.accessibilityValue() as? String ?? "")"
    }
    #expect(
      described == [
        "Changed, Line 1", "Removed, After line 2", "Added, Line 3", "Open conflict, Line 3",
        "Ignored difference, Line 4",
        "Removed text, Line 1",
      ])
    #expect(marks.allSatisfy { $0.accessibilityRole() == .image })
  }

  @Test func everyMarkOfTheGutterExplainsItselfInAHelpTagAndToVoiceOver() throws {
    let pane = PaneView()
    pane.content = PaneContent(
      text: "let a = 1\nlet b = 2\n\n\nlet c = 3\nlet d = 4\nlet e = 5",
      lineNumbers: [0, 1, -1, -1, 2, 3, 4],
      blocks: [
        PaneBlock(rows: 0..<1, style: .tinted(.a), marker: .changed),
        PaneBlock(rows: 2..<4, style: .tinted(.a), marker: .removed),
        PaneBlock(rows: 4..<5, style: .tinted(.a), marker: .added, conflict: .open),
        PaneBlock(rows: 6..<7, style: .tinted(.b), marker: .changed, conflict: .resolved),
      ],
      ignoredDifferenceRows: [5])
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200))
    defer { window.close() }
    let gutter = try #require(
      pane.subviews.first { $0.accessibilityLabel() == "Change markers" })
    let owner = try #require(gutter as? any NSViewToolTipOwner)
    let marks = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    var helps: [String] = []
    for mark in marks {
      let frame = mark.accessibilityFrameInParentSpace()
      let help = owner.view(
        gutter, stringForToolTip: 0, point: CGPoint(x: frame.midX, y: frame.midY), userData: nil)
      #expect(mark.accessibilityHelp() == help)
      #expect(help.count <= 75)
      helps.append(help)
    }
    #expect(
      helps == [
        "Differs on this side", "Lacks lines here that the other side has",
        "Appears only on this side", "Differs on both sides; choose what the result takes",
        "Differs only in whitespace or line endings, which this comparison ignores",
        "Differs on this side", "Differed on both sides; the result takes what you chose",
      ])
  }

  @Test func removalAtTheEndOfTheTextIsMarkedOnce() throws {
    // The paragraph "let a" is laid out together with the empty row after its line feed.
    let provider = Removals(at: [6])
    let pane = PaneView()
    pane.content = PaneContent(
      text: "let a\n", lineNumbers: [0, 1],
      blocks: [PaneBlock(rows: 0..<2, style: .tinted(.b))])
    pane.highlightProvider = provider
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 100))
    defer { window.close() }
    let gutter = try #require(
      pane.subviews.first { $0.accessibilityLabel() == "Change markers" })
    let marks = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
    #expect(marks.map { $0.accessibilityValue() as? String } == ["Line 2"])
  }
}

/// Marks removed text at fixed offsets of the first block.
@MainActor
private final class Removals: PaneHighlightProvider {
  private let offsets: [Int]

  init(at offsets: [Int] = [4]) {
    self.offsets = offsets
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    block == 0 ? offsets.map { $0..<$0 } : []
  }
}
