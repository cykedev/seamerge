import AppKit
import PaneKit
import Testing

/// Checks how a pane hides collapsed runs behind bars: where the rows lie, what the bar does and
/// says, and that copying and finding still reach the hidden rows.
@MainActor
@Suite struct CollapsingTests {
  @Test func collapsedRunTakesOneRowAndTheRowsBelowMoveUp() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)])
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    let textView = pane.documentView

    #expect(textView.frame.height == CodeRows.textHeight(ofRows: 21, in: pane))
    let bars = Self.bars(of: pane)
    try #require(bars.count == 1)
    #expect(bars[0].frame.minY == 10 * rowHeight)
    #expect(bars[0].frame.height == rowHeight)
    #expect(bars[0].frame.minX == 0)
    #expect(bars[0].frame.width == textView.enclosingScrollView?.frame.maxX)
    let index = textView.characterIndexForInsertion(at: CGPoint(x: 100, y: 11.5 * rowHeight))
    #expect(Self.rows(30..<31).contains(index))
    let before = textView.characterIndexForInsertion(at: CGPoint(x: 100, y: 9.5 * rowHeight))
    #expect(Self.rows(9..<10).contains(before))
    #expect(pane.hit(at: CGPoint(x: 100, y: 11.5 * rowHeight)) == PaneHit(row: 30, block: nil))
    #expect(pane.hit(at: CGPoint(x: 100, y: 10.5 * rowHeight)) == PaneHit(row: 10, block: nil))
  }

  @Test func rowsAfterABarAreDrawnOnTheirDisplayRow() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 3..<30)], height: 400)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    let textStart = pane.bounds.width - pane.documentView.visibleRect.width
    let bitmap = try Rendering.bitmap(of: pane)
    // Every row has text; the bar covers row 3 and its label starts at the code, so the space
    // far to its right stays clear.
    for displayRow in 0..<12 where displayRow != 3 {
      let top = CGFloat(displayRow) * rowHeight
      #expect(
        try Self.hasInk(in: bitmap, xs: textStart + 40..<textStart + 300, ys: top + 2..<top + 6),
        "display row \(displayRow)")
    }
    let barTop = 3 * rowHeight
    #expect(
      !(try Self.hasInk(
        in: bitmap, xs: textStart + 200..<textStart + 300, ys: barTop + 1..<barTop + rowHeight - 1))
    )
  }

  @Test func expandingARunPutsItsRowsBackInPlace() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)])
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight

    pane.collapsedRuns = []

    #expect(pane.documentView.frame.height == CodeRows.textHeight(ofRows: 40, in: pane))
    #expect(Self.bars(of: pane).isEmpty)
    let index = pane.documentView.characterIndexForInsertion(
      at: CGPoint(x: 100, y: 20.5 * rowHeight))
    #expect(Self.rows(20..<21).contains(index))
  }

  @Test func changingTheRunsKeepsTheTopRowInPlace() throws {
    let (pane, window) = Self.pane(runs: [], height: 200)
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    pane.documentView.scroll(CGPoint(x: 0, y: 28 * rowHeight))

    pane.collapsedRuns = [CollapsedRun(rows: 5..<25)]
    #expect(pane.documentView.visibleRect.minY == 9 * rowHeight)

    pane.collapsedRuns = []
    #expect(pane.documentView.visibleRect.minY == 28 * rowHeight)
  }

  @Test func barAsksToExpandItsRunWhenClickedPressedOrPressedWithReturn() throws {
    let runs = [CollapsedRun(rows: 2..<8), CollapsedRun(rows: 20..<35)]
    let (pane, window) = Self.pane(runs: runs, height: 400)
    defer { window.close() }
    let recorder = ExpansionRecorder()
    pane.delegate = recorder
    let bars = Self.bars(of: pane)
    try #require(bars.count == 2)

    bars[0].performClick(nil)
    #expect(bars[1].accessibilityPerformPress())
    let returnKey = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    bars[1].keyDown(with: returnKey)

    #expect(recorder.runs == [runs[0], runs[1], runs[1]])
    #expect(pane.collapsedRuns == runs)
  }

  @Test func barIsAButtonThatNamesTheLinesItHides() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<22)])
    defer { window.close() }
    let bar = try #require(Self.bars(of: pane).first)

    #expect(bar.accessibilityRole() == .button)
    #expect(bar.accessibilityLabel() == "12 unchanged lines, collapsed")
    #expect(bar.accessibilityHelp() == "Shows the hidden lines.")
    #expect(bar.isAccessibilityElement())
  }

  @Test func barNamesThePaneItStandsIn() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<17)])
    defer { window.close() }
    pane.setAccessibilityLabel("Base")
    let bar = try #require(Self.bars(of: pane).first)

    #expect(bar.accessibilityLabel() == "7 unchanged lines in Base, collapsed")
  }

  @Test func pressedBarIsDarkerThanAtRest() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)])
    defer { window.close() }
    let bar = try #require(Self.bars(of: pane).first)
    let point = CGPoint(x: pane.bounds.width - 40, y: 10.5 * pane.theme.rowHeight)
    let atRest = try Rendering.color(in: Rendering.bitmap(of: pane), at: point)

    bar.isHighlighted = true
    let pressed = try Rendering.color(in: Rendering.bitmap(of: pane), at: point)

    #expect(pressed.brightnessComponent < atRest.brightnessComponent)
  }

  @Test func contentWithFewerRowsReplacesRunsThatNoLongerFit() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 30..<40)])
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight

    pane.content = CodeRows.content(count: 20)
    pane.layoutSubtreeIfNeeded()
    #expect(pane.collapsedRuns.isEmpty)
    #expect(pane.documentView.frame.height == CodeRows.textHeight(ofRows: 20, in: pane))

    pane.setContent(CodeRows.content(count: 25), collapsedRuns: [CollapsedRun(rows: 10..<20)])
    pane.layoutSubtreeIfNeeded()
    #expect(pane.collapsedRuns == [CollapsedRun(rows: 10..<20)])
    #expect(pane.documentView.frame.height == CodeRows.textHeight(ofRows: 16, in: pane))
    let bars = Self.bars(of: pane)
    #expect(bars.map(\.frame.minY) == [10 * rowHeight])

    pane.setContent(CodeRows.content(count: 12), collapsedRuns: [CollapsedRun(rows: 0..<12)])
    pane.layoutSubtreeIfNeeded()
    #expect(pane.documentView.frame.height == CodeRows.textHeight(ofRows: 1, in: pane))
    #expect(Self.bars(of: pane).count == 1)
  }

  @Test func barOfASingleRowNamesOneLine() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<11)])
    defer { window.close() }
    let bar = try #require(Self.bars(of: pane).first)

    #expect(bar.accessibilityLabel() == "1 unchanged line, collapsed")
  }

  @Test func copyingAcrossABarCopiesTheRowsItHides() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)])
    defer { window.close() }
    let start = CodeRows.start(ofRow: 9)
    let end = CodeRows.start(ofRow: 31)
    pane.documentView.setSelectedRange(NSRange(location: start, length: end - start))

    let copied = try Self.copy(from: pane)

    let expected = (9..<31).map { CodeRows.line(row: $0, length: 60) + "\n" }.joined()
    #expect(copied == expected)
  }

  @Test func barShowsWhenTheSelectionTakesInItsRows() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)])
    defer { window.close() }
    let point = CGPoint(x: pane.bounds.width - 40, y: 10.5 * pane.theme.rowHeight)
    let plain = try Rendering.color(in: Rendering.bitmap(of: pane), at: point)

    pane.documentView.setSelectedRange(NSRange(location: CodeRows.start(ofRow: 9), length: 100))
    let selected = try Rendering.color(in: Rendering.bitmap(of: pane), at: point)
    pane.documentView.setSelectedRange(NSRange(location: CodeRows.start(ofRow: 31), length: 4))
    let elsewhere = try Rendering.color(in: Rendering.bitmap(of: pane), at: point)

    #expect(selected != plain)
    #expect(elsewhere == plain)
  }

  @Test func findResultBehindABarAsksToExpandItsRunAndComesIntoView() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)], height: 120)
    defer { window.close() }
    let expander = Expander()
    pane.delegate = expander
    let offset = CodeRows.start(ofRow: 25)

    pane.documentView.scrollRangeToVisible(NSRange(location: offset, length: 3))

    #expect(expander.runs == [CollapsedRun(rows: 10..<30)])
    #expect(pane.collapsedRuns.isEmpty)
    let visible = pane.documentView.visibleRect
    #expect((visible.minY..<visible.maxY).contains(25.5 * pane.theme.rowHeight))
  }

  @Test func findResultBehindABarThatStaysCollapsedShowsTheBar() throws {
    let (pane, window) = Self.pane(runs: [CollapsedRun(rows: 10..<30)], height: 60)
    defer { window.close() }

    pane.documentView.scrollRangeToVisible(
      NSRange(location: CodeRows.start(ofRow: 25), length: 3))

    let visible = pane.documentView.visibleRect
    #expect((visible.minY..<visible.maxY).contains(10.5 * pane.theme.rowHeight))
  }

  @Test func rowsLieOnTheirDisplayRowsAmongManyRunsInOneHundredThousandRows() throws {
    let theme = Theme()
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(count: 100_000, length: 40)
    // Every 50 rows, 40 rows collapse: 10 visible rows and a bar.
    pane.collapsedRuns = stride(from: 5, to: 100_000 - 45, by: 50).map {
      CollapsedRun(rows: $0..<$0 + 40)
    }
    let window = Rendering.host(
      pane, size: CGSize(width: 600, height: 400), appearance: Look.all[0].appearance)
    defer { window.close() }
    let textView = pane.documentView
    #expect(textView.frame.height == CGFloat(100_000 - 1_999 * 39) * theme.rowHeight)
    for displayRow in [0, 11, 5_000, 21_000, 21_900] {
      textView.scroll(CGPoint(x: 0, y: CGFloat(displayRow) * theme.rowHeight))
      let first = Int(textView.visibleRect.minY / theme.rowHeight)
      for shown in first..<first + 12 {
        let group = shown / 11
        let place = shown % 11
        guard place != 5 else { continue }
        let row = group * 50 + (place < 5 ? place : place + 39)
        let index = textView.characterIndexForInsertion(
          at: CGPoint(x: 100, y: (CGFloat(shown) + 0.5) * theme.rowHeight))
        #expect(
          CodeRows.start(ofRow: row, length: 40)..<CodeRows.start(ofRow: row + 1, length: 40)
            ~= index, "display row \(shown) shows row \(row)")
      }
    }
  }

  /// Forty rows of code, with `runs`, in a pane `height` points high.
  private static func pane(runs: [CollapsedRun], height: CGFloat = 900) -> (PaneView, NSWindow) {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 40)
    pane.collapsedRuns = runs
    let window = Rendering.host(
      pane, size: CGSize(width: 600, height: height), appearance: Look.all[0].appearance)
    return (pane, window)
  }

  /// The bars of `pane` that are in view, top to bottom.
  static func bars(of pane: NSView) -> [NSButton] {
    var bars: [NSButton] = []
    func collect(_ view: NSView) {
      if let button = view as? NSButton, button.accessibilityRole() == .button,
        button.accessibilityLabel()?.contains("unchanged") == true
      {
        bars.append(button)
      }
      view.subviews.forEach(collect)
    }
    collect(pane)
    return bars.sorted { $0.frame.minY < $1.frame.minY }
  }

  /// The UTF-16 offsets of `rows` of the forty rows of code, line feeds included.
  private static func rows(_ rows: Range<Int>) -> Range<Int> {
    CodeRows.start(ofRow: rows.lowerBound)..<CodeRows.start(ofRow: rows.upperBound)
  }

  private static func hasInk(
    in bitmap: NSBitmapImageRep, xs: Range<CGFloat>, ys: Range<CGFloat>
  ) throws -> Bool {
    let background = try Rendering.color(in: bitmap, at: CGPoint(x: xs.upperBound + 200, y: 1))
    for y in stride(from: ys.lowerBound, to: ys.upperBound, by: 1) {
      for x in stride(from: xs.lowerBound, to: xs.upperBound, by: 1) {
        let color = try Rendering.color(in: bitmap, at: CGPoint(x: x, y: y))
        if abs(color.redComponent - background.redComponent) > 0.2 {
          return true
        }
      }
    }
    return false
  }

  /// Copies the selection of `pane` to a pasteboard of its own, never the user's clipboard.
  private static func copy(from pane: PaneView) throws -> String? {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("Seamerge.Tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let textView = pane.documentView
    try #require(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
    return pasteboard.string(forType: .string)
  }
}

/// Records the runs that a pane asks to expand, and leaves them collapsed.
@MainActor
private final class ExpansionRecorder: PaneViewDelegate {
  var runs: [CollapsedRun] = []
  var collapses: [CollapsedRun] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {}

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? { nil }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    runs.append(run)
  }

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {
    collapses.append(run)
  }
}

/// Expands every run that a pane asks to expand, as the window does.
@MainActor
private final class Expander: PaneViewDelegate {
  var runs: [CollapsedRun] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {}

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? { nil }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    runs.append(run)
    pane.collapsedRuns.removeAll { $0 == run }
  }

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {}
}
