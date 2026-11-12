import AppKit
import PaneKit
import Testing

/// Draws the pictures of collapsed runs for the visual review: a merge and a comparison with
/// their unchanged lines collapsed, and the same with one run expanded.
@MainActor
@Suite struct CollapsedPicturesTests {
  @Test(arguments: Look.all, [false, true])
  func collapsedMergeIsPictured(look: Look, expandsOneRun: Bool) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let layout = CoupledLayout(merge: .transcoderWithLongUnchangedRuns, repeats: 3, theme: theme)
    let window = Rendering.host(
      layout, size: CGSize(width: 1280, height: 760), appearance: look.appearance)
    defer { window.close() }
    layout.collapseUnchangedRows(except: expandsOneRun ? 1 : nil)
    layout.setCurrentBlock(SampleMerge.openConflictBlock)
    try Rendering.write(
      Rendering.bitmap(of: layout),
      named: "merge-\(expandsOneRun ? "one-run-expanded" : "collapsed")-\(look.name)")
  }

  @Test(arguments: Look.all, [false, true])
  func collapsedComparisonIsPictured(look: Look, expandsOneRun: Bool) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let layout = MergeLayout(diffOf: .transcoderWithLongUnchangedRuns, theme: theme)
    let window = Rendering.host(
      layout, size: CGSize(width: 1280, height: 520), appearance: look.appearance)
    defer { window.close() }
    let runs = layout.upperPanes[0].content.collapsibleRuns
    for pane in layout.upperPanes {
      pane.collapsedRuns = runs.indices.filter { !expandsOneRun || $0 != 0 }.map { runs[$0] }
    }
    try Rendering.write(
      Rendering.bitmap(of: layout),
      named: "diff-\(expandsOneRun ? "one-run-expanded" : "collapsed")-\(look.name)")
  }

  @Test func collapsedMergeWithoutColorAndAtItsSmallestIsPictured() throws {
    let look = Look.all[0]
    let colorless = CoupledLayout(
      merge: .transcoderWithLongUnchangedRuns, repeats: 3,
      theme: Theme(differentiatesWithoutColor: true))
    let window = Rendering.host(
      colorless, size: CGSize(width: 1280, height: 760), appearance: look.appearance)
    colorless.collapseUnchangedRows()
    try Rendering.write(Rendering.bitmap(of: colorless), named: "merge-collapsed-without-color")
    window.close()

    let smallest = CoupledLayout(
      merge: .transcoderWithLongUnchangedRuns, repeats: 3, theme: Theme())
    let width = smallest.upperPanes.map(\.minimumWidth).reduce(0, +) + 2
    let smallWindow = Rendering.host(
      smallest, size: CGSize(width: width, height: 480), appearance: look.appearance)
    defer { smallWindow.close() }
    smallest.collapseUnchangedRows()
    try Rendering.write(Rendering.bitmap(of: smallest), named: "merge-collapsed-smallest-light")
  }

  @Test func focusedBarAndSelectionAcrossABarArePictured() throws {
    for look in Look.all.prefix(2) {
      let layout = CoupledLayout(
        merge: .transcoderWithLongUnchangedRuns, repeats: 3, theme: Theme())
      let window = Rendering.host(
        layout, size: CGSize(width: 1280, height: 400), appearance: look.appearance, isKey: true)
      layout.collapseUnchangedRows()
      let pane = layout.upperPanes[0]
      window.makeFirstResponder(pane.documentView)
      let text = pane.content.text as NSString
      pane.documentView.setSelectedRange(NSRange(location: 20, length: text.length / 4))
      let bars = CollapsingTests.bars(of: layout.upperPanes[2])
      if let bar = bars.first {
        window.makeFirstResponder(bar)
      }
      // The bar in the result as it looks while the mouse holds it down.
      CollapsingTests.bars(of: layout.resultPane).first?.isHighlighted = true
      try Rendering.write(
        Rendering.bitmap(of: layout), named: "bar-focus-selection-pressed-\(look.name)")
      window.close()
    }
  }
}
