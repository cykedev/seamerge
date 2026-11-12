import AppKit
import PaneKit
import Testing

/// Draws the pictures of the coupled panes with their overview bars and of the invisible
/// characters, for the visual review.
@MainActor
@Suite struct CoupledPicturesTests {
  @Test(arguments: Look.all)
  func coupledPanesWithOverviewBarsArePictured(look: Look) throws {
    try picture(
      theme: Theme(increasesContrast: look.increasesContrast), look: look,
      size: CGSize(width: 1280, height: 760), named: "coupled-\(look.name)")
  }

  @Test(arguments: Look.all.prefix(2))
  func overviewBarsWithoutColorArePictured(look: Look) throws {
    try picture(
      theme: Theme(differentiatesWithoutColor: true), look: look,
      size: CGSize(width: 1280, height: 760), named: "coupled-without-color-\(look.name)")
  }

  @Test func coupledPanesAtTheirMinimumWidthArePictured() throws {
    let probe = CoupledLayout(merge: .transcoder, repeats: 1, theme: Theme())
    let width =
      probe.upperPanes.map(\.minimumWidth).reduce(0, +) + 2
    try picture(
      theme: Theme(), look: Look.all[0], size: CGSize(width: width, height: 480),
      named: "coupled-smallest-light")
  }

  @Test(arguments: Look.all)
  func invisibleCharactersArePictured(look: Look) throws {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let rows: [(text: String, ending: LineEnding, style: BlockStyle)] = [
      ("func decode(_ bytes: Data) -> String? {", .lineFeed, .unchanged),
      ("\tlet text = String(bytes: bytes, encoding: .utf8)", .carriageReturnLineFeed, .tinted(.a)),
      ("    return text  // two spaces before the comment", .carriageReturn, .tinted(.b)),
      ("\t\treturn nil", .lineFeed, .tinted(.conflict)),
      ("", .lineFeed, .original),
      ("}", .none, .unchanged),
    ]
    let pane = PaneView(theme: theme)
    pane.content = PaneContent(
      text: rows.map(\.text).joined(separator: "\n"), lineNumbers: rows.indices.map(Int32.init),
      blocks: rows.indices.filter { rows[$0].style != .unchanged }.map {
        PaneBlock(rows: $0..<$0 + 1, style: rows[$0].style)
      }, lineEndings: rows.map(\.ending))
    pane.showsInvisibles = true
    let window = Rendering.host(
      pane, size: CGSize(width: 520, height: 140), appearance: look.appearance, isKey: true)
    defer { window.close() }
    window.makeFirstResponder(pane.documentView)
    pane.documentView.setSelectedRange(NSRange(location: 52, length: 40))
    try Rendering.write(Rendering.bitmap(of: pane), named: "invisibles-\(look.name)")
  }

  private func picture(theme: Theme, look: Look, size: CGSize, named name: String) throws {
    let layout = CoupledLayout(merge: .transcoder, repeats: 6, theme: theme)
    let window = Rendering.host(layout, size: size, appearance: look.appearance)
    defer { window.close() }
    layout.setCurrentBlock(SampleMerge.openConflictBlock + 7)
    layout.upperPanes[0].reveal(block: SampleMerge.openConflictBlock + 7)
    try Rendering.write(Rendering.bitmap(of: layout), named: name)
  }
}
