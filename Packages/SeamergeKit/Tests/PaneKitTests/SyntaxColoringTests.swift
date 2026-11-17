import AppKit
import PaneKit
import Testing

/// Checks how a pane colors its code by the tokens of its syntax provider: in the colors of the
/// theme, by the line number of each row, never within the changed runs of a block, within
/// previews or beyond the cut of a long line, and anew when the tokens change.
@MainActor
@Suite struct SyntaxColoringTests {
  /// Two lines of code around a comment; the rows start at 0, 10 and 18.
  static let text = "let a = 1\n// note\nlet b = 2"

  /// The tokens of the three lines of ``text``.
  static let tokens: [Int: [PaneToken]] = [
    0: [PaneToken(range: 0..<3, kind: .keyword), PaneToken(range: 8..<9, kind: .number)],
    1: [PaneToken(range: 0..<7, kind: .comment)],
    2: [PaneToken(range: 0..<3, kind: .keyword), PaneToken(range: 8..<9, kind: .number)],
  ]

  @Test func tokensAreDrawnInTheSyntaxColorsOfTheTheme() throws {
    let shown = Self.show(Self.content(), tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    let theme = pane.theme
    #expect(try Self.color(at: 1, in: pane) == Self.resolved(theme.syntaxColor(for: .keyword)))
    #expect(try Self.color(at: 8, in: pane) == Self.resolved(theme.syntaxColor(for: .number)))
    #expect(try Self.color(at: 12, in: pane) == Self.resolved(theme.syntaxColor(for: .comment)))
    #expect(try Self.color(at: 4, in: pane) == nil)
  }

  @Test func changedRunsWithinABlockKeepTheColorOfText() throws {
    var content = Self.content()
    content.blocks = [PaneBlock(rows: 2..<3, style: .tinted(.b))]
    let shown = Self.show(
      content, tokens: Tokens(Self.tokens), highlights: Highlights([0: [22..<27]]))
    defer { shown.window.close() }
    let pane = shown.pane
    #expect(try Self.color(at: 26, in: pane) == nil)
    #expect(
      try Self.color(at: 18, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
  }

  @Test func previewsKeepTheirOwnColor() throws {
    var content = Self.content()
    content.previews = [PanePreview(range: 10..<18, role: .a)]
    let shown = Self.show(content, tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    #expect(try Self.color(at: 12, in: pane) == Self.resolved(pane.theme.previewTextColor))
  }

  @Test func rowsTakeTheTokensOfTheLineTheyShowAndFillersNone() throws {
    let content = PaneContent(text: "let a = 1\n\nlet b = 2", lineNumbers: [0, -1, 1])
    let shown = Self.show(content, tokens: Tokens([1: [PaneToken(range: 4..<5, kind: .keyword)]]))
    defer { shown.window.close() }
    let pane = shown.pane
    #expect(shown.tokens.askedLines.isSubset(of: [0, 1]))
    #expect(
      try Self.color(at: 15, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
    #expect(try Self.color(at: 4, in: pane) == nil)
  }

  @Test func changedTokensAreDrawnOnceThePaneIsTold() throws {
    let shown = Self.show(Self.content(), tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    shown.tokens.tokens[0] = [PaneToken(range: 4..<5, kind: .string)]
    pane.syntaxDidChange(inRows: 0..<1)
    #expect(try Self.color(at: 1, in: pane) == nil)
    #expect(try Self.color(at: 4, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .string)))
    #expect(
      try Self.color(at: 18, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
  }

  @Test func withoutAProviderCodeHasTheColorOfText() throws {
    let shown = Self.show(Self.content(), tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    pane.syntaxProvider = nil
    Self.layOut(pane)
    for offset in [1, 8, 12, 18] {
      #expect(try Self.color(at: offset, in: pane) == nil, "offset \(offset)")
    }
  }

  @Test func changedTokensOfRowsOutOfViewAreDrawnOnceTheyAreLaidOut() throws {
    let rowCount = 300
    let text = Array(repeating: "let a = 1", count: rowCount).joined(separator: "\n")
    let content = PaneContent(text: text, lineNumbers: (0..<rowCount).map(Int32.init))
    let shown = Self.show(content, tokens: Tokens([:]))
    defer { shown.window.close() }
    let pane = shown.pane
    let line = 250
    shown.tokens.tokens[line] = [PaneToken(range: 0..<3, kind: .keyword)]

    pane.syntaxDidChange(inRows: line..<line + 1)
    try Self.scroll(pane, toOffset: line * 10)

    #expect(
      try Self.color(at: line * 10 + 1, in: pane)
        == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
  }

  @Test func rowsKeepTheirColorsWhenTheSameTextIsShownAgain() throws {
    let rowCount = 300
    let line = 250
    let text = Array(repeating: "let a = 1", count: rowCount).joined(separator: "\n")
    let content = PaneContent(text: text, lineNumbers: (0..<rowCount).map(Int32.init))
    let keyword = [PaneToken(range: 0..<3, kind: .keyword)]
    let shown = Self.show(content, tokens: Tokens([0: keyword, line: keyword]))
    defer { shown.window.close() }
    let pane = shown.pane

    var blocks = content
    blocks.blocks = [PaneBlock(rows: 0..<1, style: .tinted(.a))]
    pane.setContent(blocks, collapsedRuns: [])
    Self.layOut(pane)
    #expect(try Self.color(at: 1, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
    try Self.scroll(pane, toOffset: line * 10)

    #expect(
      try Self.color(at: line * 10 + 1, in: pane)
        == Self.resolved(pane.theme.syntaxColor(for: .keyword)))
  }

  @Test func tokensBeyondTheirRowAreCutAtItsEnd() throws {
    let shown = Self.show(
      Self.content(), tokens: Tokens([0: [PaneToken(range: 4..<40, kind: .string)]]))
    defer { shown.window.close() }
    let pane = shown.pane
    #expect(try Self.color(at: 8, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .string)))
    #expect(try Self.color(at: 12, in: pane) == nil)
  }

  @Test func tokensTakeTheChangedRunsOfABlockThatChangedIntoAccount() throws {
    var content = Self.content()
    content.blocks = [PaneBlock(rows: 2..<3, style: .tinted(.b))]
    let highlights = Highlights([:])
    let shown = Self.show(content, tokens: Tokens(Self.tokens), highlights: highlights)
    defer { shown.window.close() }
    let pane = shown.pane
    let keyword = Self.resolved(pane.theme.syntaxColor(for: .keyword))
    #expect(try Self.color(at: 18, in: pane) == keyword)

    // The block changes, and with it its changed runs, which now cover the keyword.
    highlights.runs = [0: [18..<21]]
    pane.setBlocks([PaneBlock(rows: 2..<3, style: .tinted(.a))], previews: [], rowTints: [:])
    Self.layOut(pane)
    #expect(try Self.color(at: 18, in: pane) == nil)

    highlights.runs = [:]
    pane.setBlocks([PaneBlock(rows: 2..<3, style: .tinted(.b))], previews: [], rowTints: [:])
    Self.layOut(pane)
    #expect(try Self.color(at: 18, in: pane) == keyword)
  }

  @Test func tokensTakeTheChangedRunsOfANewHighlightProviderIntoAccount() throws {
    var content = Self.content()
    content.blocks = [PaneBlock(rows: 2..<3, style: .tinted(.b))]
    let shown = Self.show(content, tokens: Tokens(Self.tokens), highlights: Highlights([:]))
    defer { shown.window.close() }
    let pane = shown.pane
    let highlights = Highlights([0: [18..<21]])

    pane.highlightProvider = highlights
    Self.layOut(pane)

    #expect(try Self.color(at: 18, in: pane) == nil)
  }

  @Test func tokensThatChangeDuringAnEditAreDrawnOnceTheEditIsOver() throws {
    let shown = Self.show(Self.content(), tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    let storage = try #require(pane.documentView.textStorage)
    storage.beginEditing()
    storage.replaceCharacters(in: NSRange(location: 4, length: 1), with: "z")
    // The owner learns of new tokens while the edit is under way.
    shown.tokens.tokens[2] = [PaneToken(range: 4..<5, kind: .string)]
    pane.syntaxDidChange(inRows: 2..<3)
    storage.endEditing()
    Self.layOut(pane)

    #expect(try Self.color(at: 22, in: pane) == Self.resolved(pane.theme.syntaxColor(for: .string)))
    #expect(try Self.color(at: 18, in: pane) == nil)
  }

  @Test func rowsThatWaitForAnEditMoveAlongWithIt() throws {
    let shown = Self.show(Self.content(), tokens: Tokens(Self.tokens))
    defer { shown.window.close() }
    let pane = shown.pane
    let storage = try #require(pane.documentView.textStorage)
    let inserted = "a\nb\nc\n"
    storage.beginEditing()
    storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: inserted)
    // The last row, row 2 before the edit, gets new tokens while the edit is under way; after
    // it, the row is row 5 and shows line 5.
    shown.tokens.tokens[5] = [PaneToken(range: 4..<5, kind: .string)]
    pane.syntaxDidChange(inRows: 2..<3)
    storage.endEditing()
    Self.layOut(pane)

    let lastRow = inserted.utf16.count + 18
    #expect(
      try Self.color(at: lastRow + 4, in: pane)
        == Self.resolved(pane.theme.syntaxColor(for: .string)))
  }

  @Test func tokensBeyondTheCutOfALongLineAreLeftOut() throws {
    let length = PaneView.maximumShownLineLength + 5_000
    let line = String(repeating: "a", count: length)
    let tokens = stride(from: 0, to: length, by: 10).map {
      PaneToken(range: $0..<$0 + 5, kind: .string)
    }
    let shown = Self.show(
      PaneContent(text: line, lineNumbers: [0]), tokens: Tokens([0: tokens]))
    defer { shown.window.close() }
    let pane = shown.pane
    let manager = try #require(pane.documentView.textLayoutManager)
    let fragment = try #require(manager.textLayoutFragment(for: manager.documentRange.location))
    let paragraph = try #require(fragment.textElement as? NSTextParagraph)
    let string = Self.resolved(pane.theme.syntaxColor(for: .string))
    var colored = 0
    paragraph.attributedString.enumerateAttribute(
      .foregroundColor, in: NSRange(location: 0, length: paragraph.attributedString.length)
    ) { value, range, _ in
      if let color = value as? NSColor, Self.resolved(color) == string {
        colored += 1
        #expect(range.upperBound <= PaneView.maximumShownLineLength)
      }
    }
    #expect(colored == PaneView.maximumShownLineLength / 10)
  }

  /// The content of ``text``, one line per row.
  private static func content() -> PaneContent {
    PaneContent(text: text, lineNumbers: [0, 1, 2])
  }

  /// A pane in a light window, laid out, with the providers it does not retain.
  private struct Shown {
    let pane: PaneView
    let window: NSWindow
    let tokens: Tokens
    let highlights: Highlights?
  }

  /// Shows `content` with the tokens of `provider` and the changed runs of `highlights`.
  private static func show(
    _ content: PaneContent, tokens: Tokens, highlights: Highlights? = nil
  ) -> Shown {
    let pane = PaneView()
    pane.highlightProvider = highlights
    pane.content = content
    pane.syntaxProvider = tokens
    let window = Rendering.host(
      pane, size: CGSize(width: 400, height: 200), appearance: NSAppearance(named: .aqua))
    layOut(pane)
    return Shown(pane: pane, window: window, tokens: tokens, highlights: highlights)
  }

  /// Scrolls `offset` of the text of `pane` into view and draws it there.
  private static func scroll(_ pane: PaneView, toOffset offset: Int) throws {
    pane.documentView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    pane.window?.contentView?.layoutSubtreeIfNeeded()
    _ = try Rendering.bitmap(of: pane)
  }

  /// Lays out the whole text of `pane`, as drawing it would.
  private static func layOut(_ pane: PaneView) {
    pane.window?.contentView?.layoutSubtreeIfNeeded()
    if let manager = pane.documentView.textLayoutManager {
      manager.ensureLayout(for: manager.documentRange)
    }
  }

  /// The color that the text at `offset` is drawn in, resolved in the light appearance, or `nil`
  /// for the color of text.
  private static func color(at offset: Int, in pane: PaneView) throws -> [CGFloat]? {
    try DrawnColors.color(at: offset, in: pane.documentView).map(resolved)
  }

  /// The sRGB components of `color` in the light appearance.
  private static func resolved(_ color: NSColor) -> [CGFloat] {
    var components: [CGFloat] = []
    NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
      let rgb = color.usingColorSpace(.sRGB) ?? color
      components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
    }
    return components
  }
}

/// Tokens by line, as a test sets them, remembering which lines the pane asked for.
@MainActor
private final class Tokens: PaneSyntaxProvider {
  var tokens: [Int: [PaneToken]]
  private(set) var askedLines: Set<Int> = []

  init(_ tokens: [Int: [PaneToken]]) {
    self.tokens = tokens
  }

  func tokens(inLine line: Int) -> [PaneToken] {
    askedLines.insert(line)
    return tokens[line] ?? []
  }
}

/// Changed runs by block, as a test sets them.
@MainActor
private final class Highlights: PaneHighlightProvider {
  var runs: [Int: [Range<Int>]]

  init(_ runs: [Int: [Range<Int>]]) {
    self.runs = runs
  }

  func highlights(forBlock block: Int) -> [Range<Int>] {
    runs[block] ?? []
  }
}
