import AppKit
import Testing

@testable import PaneKit

/// Draws the pictures of the decision column and the preview for the visual review: the toggles
/// of every state, many blocks close together, and a conflict's preview before and after a
/// decision, in every look.
@MainActor
@Suite struct DecisionPicturesTests {
  @Test(arguments: Look.all)
  func everyStateOfTheDecisionColumnIsPictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let (pane, _, window, _) = DecisionColumnTests.resultPane(
      theme: theme, appearance: look.appearance)
    defer { window.close() }
    pane.currentBlock = SampleResult.Block.chosenB.rawValue
    try Rendering.write(Rendering.bitmap(of: pane), named: "column-\(look.name)")
  }

  @Test(arguments: Look.all)
  func manyBlocksCloseTogetherArePictured(look: Look) throws {
    let (pane, _, window) = DecisionColumnTests.densePane(height: 520)
    defer { window.close() }
    window.appearance = look.appearance
    pane.theme = Theme(increasesContrast: look.increasesContrast)
    pane.decisionColumn?.theme = pane.theme
    try Rendering.write(Rendering.bitmap(of: pane), named: "dense-\(look.name)")
  }

  /// The sizes of the code that the View menu steps through, from the smallest to the largest.
  private static let fontSizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32]

  @Test(arguments: [Look.all[0], Look.all[1]])
  func blocksOnLinesOneAfterTheOtherArePicturedAtEverySize(look: Look) throws {
    for size in Self.fontSizes {
      let theme = Theme(
        font: .monospacedSystemFont(ofSize: size, weight: .regular),
        increasesContrast: look.increasesContrast)
      let (pane, _, window) = DecisionColumnTests.consecutivePane(theme: theme)
      defer { window.close() }
      window.appearance = look.appearance
      let height = 11 * theme.rowHeight
      window.setContentSize(CGSize(width: 520, height: height))
      pane.frame = CGRect(x: 0, y: 0, width: 520, height: height)
      try Rendering.write(
        Rendering.bitmap(of: pane), named: "sizes-\(Int(size))pt-\(look.name)")
    }
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
    // A toggle while the mouse holds it down, and a shared one, whose cells press together. A
    // drawing without a screen shows no focus ring.
    let pressed = snippets.panes[blocks.count]
    snippets.show(.automaticB, in: pressed)
    Self.toggles(of: pressed, block: .automaticB)[1].isHighlighted = true
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
    let (pane, _, window, _) = DecisionColumnTests.resultPane(
      theme: colorless, appearance: look.appearance)
    try Rendering.write(Rendering.bitmap(of: pane), named: "column-without-color-light")
    window.close()

    let (smallest, _, smallWindow, _) = DecisionColumnTests.resultPane(appearance: look.appearance)
    defer { smallWindow.close() }
    smallWindow.setContentSize(CGSize(width: smallest.minimumWidth, height: 640))
    smallest.frame = CGRect(x: 0, y: 0, width: smallest.minimumWidth, height: 640)
    try Rendering.write(Rendering.bitmap(of: smallest), named: "column-smallest-light")
  }

  private static func toggles(
    of pane: PaneView, block: SampleResult.Block
  ) -> [DecisionToggleButton] {
    pane.decisionColumn.map {
      DecisionColumnTests.cells(of: DecisionColumnTests.row(block, in: $0))
    }
      ?? []
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
