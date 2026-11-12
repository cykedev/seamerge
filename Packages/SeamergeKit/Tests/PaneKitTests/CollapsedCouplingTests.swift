import AppKit
import PaneKit
import Testing

/// Checks that the overview bar, the gutter and the scroll coupling work on the rows that a pane
/// shows, with its collapsed runs.
@MainActor
@Suite struct CollapsedCouplingTests {
  @Test func overviewBarMarksABlockWhereThePaneShowsIt() throws {
    let theme = Theme()
    let appearance = Look.all[0].appearance
    let pane = PaneView(theme: theme)
    pane.content = CodeRows.content(
      count: 100, blocks: [PaneBlock(rows: 90..<91, style: .tinted(.a))])
    pane.collapsedRuns = [CollapsedRun(rows: 0..<80)]
    let bar = OverviewBar()
    bar.marks = [
      OverviewMark(
        rows: 90..<91, style: .tinted(.a), placement: .fullWidth, block: 0,
        accessibilityLabel: "Changed in A")
    ]
    pane.overviewBar = bar
    // All 21 display rows fit, so that no knob lies over the marks.
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 500), appearance: appearance)
    defer { window.close() }
    let knobSlot = bar.rect(for: .knobSlot)
    let slot = knobSlot.isEmpty ? bar.bounds : knobSlot
    // 21 display rows: the bar of the run, then rows 80 to 99; row 90 is display row 11.
    let shownAt = slot.minY + 11.5 / 21 * slot.height
    let wouldBeAt = slot.minY + 90.5 / 100 * slot.height
    let bitmap = try Rendering.bitmap(of: pane)
    let mark = try #require(
      Contrast.resolve(theme.overviewMarkColor(for: .tinted(.a)), in: appearance))

    #expect(
      Self.isClose(
        try Rendering.color(in: bitmap, at: CGPoint(x: bar.frame.midX, y: shownAt)), mark))
    #expect(
      !Self.isClose(
        try Rendering.color(in: bitmap, at: CGPoint(x: bar.frame.midX, y: wouldBeAt)), mark))
  }

  @Test func gutterNamesTheMarksBelowABarAtTheirDisplayRows() throws {
    let pane = PaneView()
    pane.content = CodeRows.content(
      count: 40, blocks: [PaneBlock(rows: 35..<36, style: .tinted(.a), marker: .changed)])
    pane.collapsedRuns = [CollapsedRun(rows: 10..<30)]
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 600))
    defer { window.close() }
    let gutter = try #require(
      pane.subviews.first { $0.accessibilityLabel() == "Change markers" })

    let marks = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])

    try #require(marks.count == 1)
    #expect(marks[0].accessibilityValue() as? String == "Line 36")
    #expect(marks[0].accessibilityFrameInParentSpace().minY == 16 * pane.theme.rowHeight)
  }

  @Test func resultFollowsTheUpperPaneBetweenTheirCollapsedRows() throws {
    let (upper, result, window, sync) = Self.coupledPanes()
    defer { withExtendedLifetime(sync) { window.close() } }
    let rowHeight = upper.theme.rowHeight
    upper.documentView.scroll(CGPoint(x: 0, y: 30 * rowHeight))

    // The reading line of the upper pane lies at display row 32.5, which is row 231.5; the
    // result maps it to row 115.75, which it shows at display row 16.75.
    let upperDisplayRow = (30 * rowHeight + 0.25 * 200) / rowHeight
    #expect(upperDisplayRow == 32.5)
    let expected = 16.75 * rowHeight - 0.25 * result.documentView.visibleRect.height
    #expect(abs(result.documentView.visibleRect.minY - expected) < 0.001)
  }

  @Test func placeWithinABarFollowsToTheSameFractionOfTheOtherBar() throws {
    let (upper, result, window, sync) = Self.coupledPanes()
    defer { withExtendedLifetime(sync) { window.close() } }
    let rowHeight = upper.theme.rowHeight
    // Display row 20.5, half way through the bar of rows 20 to 219, is row 120; the result maps
    // it to row 60, half way through its bar of rows 10 to 109 at display row 10.
    upper.documentView.scroll(CGPoint(x: 0, y: 20.5 * rowHeight - 0.25 * 200))

    let expected = 10.5 * rowHeight - 0.25 * result.documentView.visibleRect.height
    #expect(abs(result.documentView.visibleRect.minY - expected) < 0.001)
  }

  @Test func coupledPanesKeepTheirRowsInPlaceWhileTheirRunsChangeOneAfterTheOther() throws {
    let panes = [PaneView(), PaneView()]
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 200))
    let sync = ScrollSync()
    for (index, pane) in panes.enumerated() {
      pane.content = CodeRows.content(count: 100)
      pane.frame = CGRect(x: CGFloat(index) * 300, y: 0, width: 300, height: 200)
      host.addSubview(pane)
      sync.add(pane)
    }
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    let rowHeight = panes[0].theme.rowHeight
    panes[0].documentView.scroll(CGPoint(x: 0, y: 60 * rowHeight))

    panes[0].collapsedRuns = [CollapsedRun(rows: 5..<25)]
    #expect(panes[1].documentView.visibleRect.minY == 60 * rowHeight)
    panes[1].collapsedRuns = [CollapsedRun(rows: 5..<25)]

    for pane in panes {
      #expect(pane.documentView.visibleRect.minY == 41 * rowHeight)
    }
    panes[1].documentView.scroll(CGPoint(x: 0, y: 10 * rowHeight))
    #expect(panes[0].documentView.visibleRect.minY == 10 * rowHeight)
  }

  /// An upper pane of 400 rows with rows 20 to 219 collapsed, and a result of 200 rows with rows
  /// 10 to 109 collapsed, coupled so that row *r* above is row *r* / 2 in the result.
  ///
  /// The panes hold their coupling weakly; the caller keeps it.
  private static func coupledPanes() -> (PaneView, PaneView, NSWindow, ScrollSync) {
    let upper = PaneView()
    upper.content = CodeRows.content(count: 400)
    upper.collapsedRuns = [CollapsedRun(rows: 20..<220)]
    let result = PaneView()
    result.content = CodeRows.content(count: 200)
    result.collapsedRuns = [CollapsedRun(rows: 10..<110)]
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    upper.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    result.frame = CGRect(x: 0, y: 200, width: 400, height: 160)
    let sync = ScrollSync()
    for pane in [upper, result] {
      host.addSubview(pane)
      sync.add(pane)
    }
    sync.setRowMapping(between: upper, and: result, forward: { $0 / 2 }, backward: { $0 * 2 })
    let window = Rendering.host(host, size: host.frame.size)
    return (upper, result, window, sync)
  }

  private static func isClose(_ first: NSColor, _ second: NSColor) -> Bool {
    abs(first.redComponent - second.redComponent) < 0.02
      && abs(first.greenComponent - second.greenComponent) < 0.02
      && abs(first.blueComponent - second.blueComponent) < 0.02
  }
}
