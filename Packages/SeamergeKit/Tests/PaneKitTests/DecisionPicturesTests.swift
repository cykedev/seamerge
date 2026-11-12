import AppKit
import Testing

@testable import PaneKit

/// Draws the pictures of the decision column and the preview for the visual review: every state
/// sign, the toggles of every kind of current block, and a conflict's preview before and after a
/// decision, in every look.
@MainActor
@Suite struct DecisionPicturesTests {
  @Test(arguments: Look.all)
  func everyStateOfTheDecisionColumnIsPictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let (pane, column, window, _) = DecisionColumnTests.resultPane(
      theme: theme, appearance: look.appearance)
    defer { window.close() }
    Self.hover(SampleResult.Block.chosenB, in: pane, column: column)
    try Rendering.write(Rendering.bitmap(of: pane), named: "decisions-\(look.name)")
  }

  @Test(arguments: Look.all)
  func togglesOfEveryKindOfCurrentBlockArePictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let blocks: [SampleResult.Block] = [
      .open, .automaticA, .automaticBoth, .chosenA, .chosenBThenA, .nothingTaken, .edited,
    ]
    let snippets = Snippets(count: blocks.count + 1, theme: theme)
    let window = Rendering.host(
      snippets, size: snippets.size, appearance: look.appearance, isKey: true)
    defer { window.close() }
    for (pane, block) in zip(snippets.panes, blocks) {
      snippets.show(block, in: pane)
    }
    // A toggle while the mouse holds it down. A drawing without a screen shows no focus ring.
    let pressed = snippets.panes[blocks.count]
    snippets.show(.chosenA, in: pressed)
    Self.toggles(of: pressed)[1].isHighlighted = true
    try Rendering.write(Rendering.bitmap(of: snippets), named: "toggles-\(look.name)")
  }

  @Test(arguments: Look.all)
  func previewOfAConflictIsPicturedBeforeAndAfterADecision(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let (pane, column, window, _) = DecisionColumnTests.resultPane(
      theme: theme, size: CGSize(width: 760, height: 200), appearance: look.appearance)
    defer { window.close() }
    let block = SampleResult.Block.open.rawValue
    let rows = pane.content.blocks[block].rows
    let rowHeight = theme.rowHeight
    pane.documentView.scroll(CGPoint(x: 0, y: CGFloat(rows.lowerBound - 2) * rowHeight))
    try Rendering.write(Rendering.bitmap(of: pane), named: "preview-\(look.name)")

    // Switching A on: A's line becomes text, B's preview goes.
    let previews = pane.content.previews
    let start = try #require(previews.first).range.lowerBound
    let end = try #require(previews.last).range.upperBound
    let aText = (pane.documentView.string as NSString).substring(
      with: NSRange(try #require(previews.first).range))
    pane.carryOut([PaneEdit(range: start..<end, text: aText)])
    var content = pane.content
    content.previews = []
    content.blocks[block] = PaneBlock(
      rows: rows.lowerBound..<rows.lowerBound + 1, style: .tinted(.a))
    pane.setContent(content, collapsedRuns: [])
    column.decisions[block] = BlockDecision(
      state: .chosen([.a]),
      toggles: [
        SampleResult.toggle([.a], isOn: true), SampleResult.toggle([.base], isOn: false),
        SampleResult.toggle([.b], isOn: false),
      ], canReset: true)
    try Rendering.write(Rendering.bitmap(of: pane), named: "preview-after-choosing-a-\(look.name)")
  }

  @Test func decisionColumnWithoutColorAndAtItsSmallestIsPictured() throws {
    let look = Look.all[0]
    let colorless = Theme(differentiatesWithoutColor: true)
    let (pane, column, window, _) = DecisionColumnTests.resultPane(
      theme: colorless, appearance: look.appearance)
    Self.hover(SampleResult.Block.chosenB, in: pane, column: column)
    try Rendering.write(Rendering.bitmap(of: pane), named: "decisions-without-color-light")
    window.close()

    let (smallest, _, smallWindow, _) = DecisionColumnTests.resultPane(appearance: look.appearance)
    defer { smallWindow.close() }
    smallWindow.setContentSize(CGSize(width: smallest.minimumWidth, height: 640))
    smallest.frame = CGRect(x: 0, y: 0, width: smallest.minimumWidth, height: 640)
    try Rendering.write(Rendering.bitmap(of: smallest), named: "decisions-smallest-light")
  }

  /// Rests the pointer on the first row of `block` until its toggles show.
  private static func hover(
    _ block: SampleResult.Block, in pane: PaneView, column: DecisionColumnView
  ) {
    let row = pane.content.blocks[block.rawValue].rows.lowerBound
    column.pointerMoved(to: CGPoint(x: 10, y: (CGFloat(row) + 0.5) * pane.theme.rowHeight))
    column.hoverTimer?.fire()
  }

  private static func toggles(of pane: PaneView) -> [DecisionToggleButton] {
    pane.decisionColumn.map(DecisionColumnTests.controls(of:))?.compactMap {
      $0 as? DecisionToggleButton
    } ?? []
  }
}

/// Result panes of the sample stacked one below the other, three rows each, so that one picture
/// shows the current block of several of them.
@MainActor
private final class Snippets: NSView {
  let panes: [PaneView]
  private let theme: Theme

  init(count: Int, theme: Theme) {
    self.theme = theme
    let (content, decisions) = SampleResult.transcoder.content()
    panes = (0..<count).map { _ in
      let pane = PaneView(theme: theme)
      pane.content = content
      let column = DecisionColumnView()
      column.theme = theme
      column.decisions = decisions
      pane.decisionColumn = column
      return pane
    }
    super.init(frame: .zero)
    for pane in panes {
      addSubview(pane)
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  private var snippetHeight: CGFloat { 3 * theme.rowHeight }

  var size: CGSize {
    CGSize(width: 760, height: CGFloat(panes.count) * (snippetHeight + 1) - 1)
  }

  override func layout() {
    super.layout()
    for (index, pane) in panes.enumerated() {
      pane.frame = CGRect(
        x: 0, y: CGFloat(index) * (snippetHeight + 1), width: bounds.width, height: snippetHeight)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.separatorColor.setFill()
    dirtyRect.fill()
  }

  /// Makes `block` current in `pane` and scrolls it to the middle row.
  func show(_ block: SampleResult.Block, in pane: PaneView) {
    pane.layoutSubtreeIfNeeded()
    let row = pane.content.blocks[block.rawValue].rows.lowerBound
    pane.documentView.scroll(CGPoint(x: 0, y: CGFloat(max(row - 1, 0)) * theme.rowHeight))
    pane.currentBlock = block.rawValue
  }
}
