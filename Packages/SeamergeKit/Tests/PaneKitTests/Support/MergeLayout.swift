import AppKit
import PaneKit

/// The panes of a window without the window around them: the sides next to each other, the
/// result of a merge below, with hairlines in between.
@MainActor
final class MergeLayout: NSView {
  let upperPanes: [PaneView]
  let resultPane: PaneView?
  private let highlightProviders: [SampleHighlights]
  private let upperHeight: CGFloat

  /// Lays out `merge` with `theme`: A, base and B, or A and B with the base hidden.
  ///
  /// A side is highlighted against the base, and the base pane not at all; with the base hidden,
  /// the sides are highlighted against each other.
  convenience init(merge: SampleMerge, theme: Theme, baseHidden: Bool = false) {
    let sides: [SampleMerge.Side] = baseHidden ? [.a, .b] : [.a, .base, .b]
    let contents = sides.map { merge.content(of: $0, baseHidden: baseHidden) }
    let references = sides.map { side -> PaneContent? in
      switch side {
      case .base: nil
      case .a: merge.content(of: baseHidden ? .b : .base)
      case .b: merge.content(of: baseHidden ? .a : .base)
      }
    }
    self.init(
      contents: contents, references: references, result: merge.resultContent(),
      currentBlock: SampleMerge.openConflictBlock, theme: theme)
  }

  /// Lays out a comparison of the base of `merge` with its side B, the last block current.
  convenience init(diffOf merge: SampleMerge, theme: Theme) {
    let (left, right) = merge.diffContents()
    self.init(
      contents: [left, right], references: [right, left], result: nil,
      currentBlock: left.blocks.count - 1, theme: theme)
  }

  private init(
    contents: [PaneContent], references: [PaneContent?], result: PaneContent?,
    currentBlock: Int, theme: Theme
  ) {
    upperPanes = contents.map { content in
      let pane = PaneView(theme: theme)
      pane.content = content
      pane.currentBlock = currentBlock
      return pane
    }
    highlightProviders = zip(contents, references).map { content, reference in
      SampleHighlights(content: content, reference: reference)
    }
    for (pane, provider) in zip(upperPanes, highlightProviders) {
      pane.highlightProvider = provider
    }
    resultPane = result.map { result in
      let pane = PaneView(theme: theme)
      pane.content = result
      return pane
    }
    upperHeight = CGFloat(contents[0].lineNumbers.count) * theme.rowHeight
    super.init(frame: .zero)
    for pane in upperPanes + [resultPane].compactMap(\.self) {
      addSubview(pane)
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  /// The size that shows every row of every pane with panes of `paneWidth`.
  func fittingSize(paneWidth: CGFloat) -> CGSize {
    let resultHeight = resultPane.map {
      Self.hairline + CGFloat($0.content.lineNumbers.count) * $0.theme.rowHeight
    }
    return CGSize(
      width: CGFloat(upperPanes.count) * (paneWidth + Self.hairline) - Self.hairline,
      height: upperHeight + (resultHeight ?? 0))
  }

  override func layout() {
    super.layout()
    let paneWidth =
      (bounds.width - CGFloat(upperPanes.count - 1) * Self.hairline) / CGFloat(upperPanes.count)
    for (index, pane) in upperPanes.enumerated() {
      pane.frame = CGRect(
        x: CGFloat(index) * (paneWidth + Self.hairline), y: 0, width: paneWidth,
        height: upperHeight)
    }
    resultPane?.frame = CGRect(
      x: 0, y: upperHeight + Self.hairline, width: bounds.width,
      height: bounds.height - upperHeight - Self.hairline)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.separatorColor.setFill()
    dirtyRect.fill()
  }

  private static let hairline: CGFloat = 1
}
