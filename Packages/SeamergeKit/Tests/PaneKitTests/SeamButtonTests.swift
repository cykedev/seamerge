import AppKit
import Testing

@testable import PaneKit

/// Checks the buttons at a seam that copy a change: one at each copied block in view for each
/// direction, in its half where there are two, a bin where the copy removes lines, clicks that
/// reach them and pass beside them, VoiceOver that finds them, and the delegate that learns of
/// a press; and a seam without bands where the panes line up their rows.
@MainActor
@Suite struct SeamButtonTests {
  /// The layout with buttons in `directions` at every block.
  private func hosted(
    _ directions: Set<PaneSeam.CopyDirection>, height: CGFloat = 500
  ) -> (ConnectedLayout, NSWindow) {
    let (layout, window) = ConnectedLayout.hosted(height: height)
    layout.seam.copyDirections = directions
    layout.seam.copiedBlocks = IndexSet(layout.left.content.blocks.indices)
    layout.needsLayout = true
    layout.layoutSubtreeIfNeeded()
    layout.seam.copyTexts = [
      .toRight: PaneSeam.CopyText(
        titleFormat: "Copy %lld right", help: "Replaces the lines of Right.",
        toolTip: "Copy right", removalTitleFormat: "Remove %lld right",
        removalHelp: "Removes these lines from Right.", removalToolTip: "Remove right"),
      .toLeft: PaneSeam.CopyText(
        titleFormat: "Copy %lld left", help: "Replaces the lines of Left.", toolTip: "Copy left",
        removalTitleFormat: "Remove %lld left", removalHelp: "Removes these lines from Left.",
        removalToolTip: "Remove left"),
    ]
    layout.seam.layoutSubtreeIfNeeded()
    return (layout, window)
  }

  @Test func buttonsStandAtTheBlocksInViewOnly() throws {
    let (layout, window) = hosted([.toRight], height: 240)
    defer { window.close() }
    layout.seam.showsBands = false
    layout.seam.layoutSubtreeIfNeeded()
    let blocks = layout.seam.copyButtons.map(\.block)
    #expect(!blocks.isEmpty)
    #expect(blocks.count < layout.left.content.blocks.count)
    #expect(layout.seam.copyButtons.allSatisfy { $0.direction == .toRight })
    #expect(layout.seam.copyButtons.allSatisfy { $0.frame.midX == layout.seam.bounds.midX })
    layout.right.documentView.scroll(CGPoint(x: 0, y: layout.right.documentView.frame.height))
    layout.seam.layoutSubtreeIfNeeded()
    #expect(
      layout.seam.copyButtons.last?.block == layout.left.content.blocks.count - 1)
    #expect(Set(layout.seam.copyButtons.map(\.block)).isDisjoint(with: blocks))
  }

  @Test func withoutBandsEachDirectionHasItsHalfAndTheSeamIsWiderWithBoth() throws {
    let (layout, window) = hosted([.toRight, .toLeft])
    defer { window.close() }
    layout.seam.showsBands = false
    layout.seam.layoutSubtreeIfNeeded()
    #expect(layout.seam.width == Theme.wideSeamWidth)
    let buttons = layout.seam.copyButtons
    let toRight = buttons.filter { $0.direction == .toRight }
    let toLeft = buttons.filter { $0.direction == .toLeft }
    #expect(!toRight.isEmpty && toRight.count == toLeft.count)
    #expect(toRight.allSatisfy { $0.frame.midX < layout.seam.bounds.midX })
    #expect(toLeft.allSatisfy { $0.frame.midX > layout.seam.bounds.midX })
    for (left, right) in zip(toRight, toLeft) {
      #expect(left.frame.midY == right.frame.midY)
    }
    layout.seam.copyDirections = [.toLeft]
    #expect(layout.seam.width == Theme.seamWidth)
  }

  @Test func withBandsButtonsStandOnTheFlatStartOfTheBandOnTheSideTheTextComesFrom() throws {
    let (layout, window) = hosted([.toRight, .toLeft])
    defer { window.close() }
    #expect(layout.seam.width == Theme.wideSeamWidth + Theme.bandRoomBesideButtons)
    let seam = layout.seam
    let rowHeight = layout.left.theme.rowHeight
    for button in seam.copyButtons {
      let source = button.direction == .toRight ? layout.left : layout.right
      let band = try #require(seam.bands.first { $0.block == button.block })
      let end = button.direction == .toRight ? band.left : band.right
      let x =
        button.direction == .toRight
        ? seam.bounds.minX + Theme.bandStubWidth / 2 : seam.bounds.maxX - Theme.bandStubWidth / 2
      #expect(
        abs(button.frame.midX + button.symbolOffset.width - x) <= 0.5, "block \(button.block)")
      // At the first row of the block, or on the line the band comes out of.
      let middle =
        source.content.blocks[button.block].rows.isEmpty
        ? end.lowerBound : end.lowerBound + rowHeight / 2
      #expect(
        abs(button.frame.midY + button.symbolOffset.height - middle) <= 1,
        "block \(button.block)")
    }
  }

  @Test func binStandsOnTheLineAndTheBandStartsAsATipBesideIt() throws {
    let (layout, window) = hosted([.toRight, .toLeft])
    defer { window.close() }
    let seam = layout.seam
    var bins = 0
    for band in seam.bands {
      for (pane, end, direction) in [
        (layout.left, band.left, PaneSeam.CopyDirection.toRight),
        (layout.right, band.right, .toLeft),
      ] where pane.content.blocks[band.block].rows.isEmpty {
        let button = try #require(
          seam.copyButtons.first { $0.block == band.block && $0.direction == direction })
        #expect(
          abs(button.frame.midY + button.symbolOffset.height - end.lowerBound) <= 0.5,
          "block \(band.block)")
        bins += 1
      }
    }
    #expect(bins > 0)
    #expect(Self.symbolsTouchingLines(in: seam).isEmpty, "\(Self.symbolsTouchingLines(in: seam))")
  }

  /// The layout with buttons both ways in `theme`, whose left lacks lines at its first place and
  /// at the two after it, one line apart, the tightest that bins stand, and whose right lacks the
  /// lines removed after that.
  private func denseLayout(theme: Theme) -> (ConnectedLayout, NSWindow) {
    let (layout, window) = hosted([.toRight, .toLeft])
    for view in [layout.left, layout.right] {
      view.theme = theme
    }
    layout.seam.theme = theme
    let inserted = [(0, 0), (1, 2), (2, 4)]
    var left = CodeRows.content(
      count: 8,
      blocks: inserted.map { PaneBlock(rows: $0.0..<$0.0, style: .tinted(.a), marker: .removed) }
        + [PaneBlock(rows: 4..<6, style: .tinted(.a), marker: .removed)])
    left.marksBlocksWithoutRows = true
    var right = CodeRows.content(
      count: 9,
      blocks: inserted.map { PaneBlock(rows: $0.1..<$0.1 + 1, style: .tinted(.b), marker: .added) }
        + [PaneBlock(rows: 7..<7, style: .tinted(.b), marker: .added)])
    right.marksBlocksWithoutRows = true
    layout.left.content = left
    layout.right.content = right
    layout.seam.copiedBlocks = IndexSet(0..<4)
    layout.seam.removingBlocks = [.toRight: IndexSet(0..<3), .toLeft: [3]]
    layout.layoutSubtreeIfNeeded()
    layout.seam.layoutSubtreeIfNeeded()
    return (layout, window)
  }

  /// The standard theme, compact line spacing, and the smallest size of the code in Settings at
  /// compact spacing, the lowest rows there are.
  static let themes: [Theme] = [
    Theme(), Theme(lineHeightMultiple: 1.3),
    Theme(
      font: .monospacedSystemFont(ofSize: 9, weight: .regular),
      lineHeightMultiple: 1.3),
  ]

  @Test(arguments: 0..<3)
  func noSymbolTouchesALineOrAnotherSymbolAtTheStartOfTheRows(theme index: Int) throws {
    let (layout, window) = denseLayout(theme: Self.themes[index])
    defer { window.close() }
    let top = layout.seam.convert(CGPoint.zero, from: layout.left.documentView).y
    let bins = layout.seam.copyButtons.filter(\.removesLines)
    #expect(bins.count == 4)
    for bin in bins {
      #expect(bin.frame.minY + bin.drawnSymbolFrame.minY >= top + Theme.copySymbolMargin)
    }
    #expect(
      Self.symbolsTouchingLines(in: layout.seam).isEmpty,
      "\(Self.symbolsTouchingLines(in: layout.seam))")
    // A block without band, and the seam without bands, as where the panes line up their rows.
    layout.seam.blocksWithoutBand = [1]
    layout.seam.layoutSubtreeIfNeeded()
    #expect(
      Self.symbolsTouchingLines(in: layout.seam).isEmpty,
      "\(Self.symbolsTouchingLines(in: layout.seam))")
    layout.seam.showsBands = false
    layout.needsLayout = true
    layout.layoutSubtreeIfNeeded()
    layout.seam.layoutSubtreeIfNeeded()
    #expect(!layout.seam.copyButtons.isEmpty)
    #expect(
      Self.symbolsTouchingLines(in: layout.seam).isEmpty,
      "\(Self.symbolsTouchingLines(in: layout.seam))")
  }

  @Test func binIsAsLargeAsTheArrowAwayFromOtherBins() throws {
    let (layout, window) = hosted([.toRight, .toLeft])
    defer { window.close() }
    layout.seam.removingBlocks = [
      .toRight: IndexSet(
        layout.left.content.blocks.indices.filter { layout.left.content.blocks[$0].rows.isEmpty }),
      .toLeft: IndexSet(
        layout.right.content.blocks.indices.filter {
          layout.right.content.blocks[$0].rows.isEmpty
        }),
    ]
    layout.seam.layoutSubtreeIfNeeded()
    let arrow = try #require(layout.seam.copyButtons.first { !$0.removesLines })
    let bins = layout.seam.copyButtons.filter(\.removesLines)
    #expect(!bins.isEmpty)
    for bin in bins {
      #expect(bin.largestSymbolSize == arrow.largestSymbolSize, "bin \(bin.block)")
      #expect(bin.drawnSymbolFrame.width == arrow.drawnSymbolFrame.width, "bin \(bin.block)")
    }
  }

  @Test(arguments: 0..<3)
  func binIsSmallerOnlyBesideABinOneRowAway(theme index: Int) throws {
    let (layout, window) = denseLayout(theme: Self.themes[index])
    defer { window.close() }
    let buttons = layout.seam.copyButtons
    let arrow = try #require(buttons.first { !$0.removesLines })
    // The three bins on the left lie one row apart, the first at the top of the rows, where it
    // moves down; the bin on the right has no bin beside it.
    let close = buttons.filter { $0.removesLines && $0.direction == .toRight }
      .sorted { $0.block < $1.block }
    let alone = try #require(buttons.first { $0.removesLines && $0.direction == .toLeft })
    try #require(close.count == 3)
    for bin in close.prefix(2) {
      #expect(bin.drawnSymbolFrame.height < alone.drawnSymbolFrame.height, "bin \(bin.block)")
    }
    #expect(close[2].drawnSymbolFrame.height <= alone.drawnSymbolFrame.height)
    #expect(alone.largestSymbolSize == arrow.largestSymbolSize)
    #expect(Self.symbolsTouchingLines(in: layout.seam).isEmpty)
  }

  @Test func overlappingClickAreasGoToTheButtonWhoseMiddleIsNearest() throws {
    let (layout, window) = denseLayout(theme: Theme(lineHeightMultiple: 1.3))
    defer { window.close() }
    let seam = layout.seam
    let bins = seam.copyButtons.filter { $0.direction == .toRight && $0.block < 2 }
      .sorted { $0.block < $1.block }
    try #require(bins.count == 2)
    let overlap = bins[0].frame.intersection(bins[1].frame)
    try #require(!overlap.isEmpty, "the click areas of bins one row apart overlap")
    for y in stride(from: overlap.minY + 0.25, to: overlap.maxY, by: 0.5) {
      let point = CGPoint(x: overlap.midX, y: y)
      let nearest = bins.min {
        abs($0.frame.midY - y) < abs($1.frame.midY - y)
      }
      let hit = seam.hitTest(seam.convert(point, to: layout))
      #expect(hit === nearest, "at \(y)")
      #expect(seam.hitTest(seam.convert(point, to: layout)) === hit, "the same every time")
    }
  }

  @Test(arguments: [true, false])
  func clickAreasAreWholeAndLieWithinTheSeam(showsBands: Bool) throws {
    let (layout, window) = denseLayout(theme: Theme())
    defer { window.close() }
    let seam = layout.seam
    seam.showsBands = showsBands
    layout.needsLayout = true
    layout.layoutSubtreeIfNeeded()
    seam.layoutSubtreeIfNeeded()
    #expect(!seam.copyButtons.isEmpty)
    for button in seam.copyButtons {
      let frame = button.frame
      #expect(frame.width == Theme.copyButtonSize && frame.height == Theme.copyButtonSize)
      #expect(seam.bounds.contains(frame), "\(button.direction) \(button.block) \(frame)")
      let center = seam.convert(CGPoint(x: frame.midX, y: frame.midY), to: layout)
      #expect(seam.hitTest(center) === button)
      for corner in [
        CGPoint(x: frame.minX + 0.5, y: frame.midY), CGPoint(x: frame.maxX - 0.5, y: frame.midY),
      ] {
        #expect(seam.hitTest(seam.convert(corner, to: layout)) === button)
      }
    }
  }

  /// The symbols of the buttons of `seam` that come closer than their margin to the edge of a
  /// band, to the lines at the sides of the seam, or to another symbol.
  static func symbolsTouchingLines(in seam: PaneSeam) -> [String] {
    let margin = Theme.copySymbolMargin
    let symbols = seam.copyButtons.map { button in
      (
        name: "\(button.direction) \(button.block)",
        rect: button.drawnSymbolFrame.offsetBy(dx: button.frame.minX, dy: button.frame.minY)
      )
    }
    var touching: [String] = []
    let hairline = 1 / (seam.window?.backingScaleFactor ?? 2)
    for symbol in symbols {
      let room = CGPath(rect: symbol.rect.insetBy(dx: -margin, dy: -margin), transform: nil)
      for band in seam.bands {
        let edges = seam.outline(of: band)
        for edge in [edges.top, edges.bottom] {
          let line = edge.copy(
            strokingWithWidth: hairline, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
          if line.intersects(room) {
            touching.append("\(symbol.name) touches the edge of band \(band.block)")
          }
        }
      }
      if symbol.rect.minX < seam.bounds.minX + hairline + margin
        || symbol.rect.maxX > seam.bounds.maxX - hairline - margin
      {
        touching.append("\(symbol.name) touches a side of the seam")
      }
      for other in symbols where other.name != symbol.name {
        if other.rect.insetBy(dx: -margin / 2, dy: -margin / 2).intersects(
          symbol.rect.insetBy(dx: -margin / 2, dy: -margin / 2))
        {
          touching.append("\(symbol.name) touches \(other.name)")
        }
      }
    }
    return touching
  }

  @Test func copyThatRemovesLinesShowsABinAndSaysSo() throws {
    let (layout, window) = hosted([.toLeft])
    defer { window.close() }
    // The right has no rows in the removal, so copying it to the left removes the lines there.
    layout.seam.removingBlocks = [.toLeft: [ConnectedLayout.removal]]
    layout.seam.layoutSubtreeIfNeeded()
    let bin = try #require(
      layout.seam.copyButtons.first { $0.block == ConnectedLayout.removal })
    #expect(bin.removesLines)
    #expect(bin.symbolName == "trash")
    #expect(bin.accessibilityLabel() == "Remove \(ConnectedLayout.removal + 1) left")
    #expect(bin.accessibilityHelp() == "Removes these lines from Left.")
    #expect(bin.toolTip == "Remove left")
    let arrow = try #require(layout.seam.copyButtons.first { !$0.removesLines })
    #expect(arrow.symbolName == "arrow.left")
    #expect(arrow.accessibilityLabel() == "Copy \(arrow.block + 1) left")
    #expect(arrow.accessibilityHelp() == "Replaces the lines of Left.")
  }

  @Test func clicksReachTheButtonsAndPassBesideThem() throws {
    let (layout, window) = hosted([.toRight])
    defer { window.close() }
    let delegate = SeamDelegate()
    layout.seam.delegate = delegate
    let button = try #require(layout.seam.copyButtons.first)
    let center = layout.seam.convert(
      CGPoint(x: button.frame.midX, y: button.frame.midY), to: layout)
    #expect(layout.seam.hitTest(center) === button)
    #expect(layout.seam.hitTest(CGPoint(x: center.x, y: center.y - 20)) == nil)
    #expect(layout.seam.accessibilityChildren()?.count == layout.seam.copyButtons.count)
    #expect(button.accessibilityRole() == .button)
    #expect(button.accessibilityPerformPress())
    #expect(delegate.presses.map(\.block) == [button.block])
    #expect(delegate.presses.map(\.direction) == [.toRight])
  }

  @Test func buttonsTakeNoPressesWhileTheSeamSaysSo() throws {
    let (layout, window) = hosted([.toRight])
    defer { window.close() }
    layout.seam.copyButtonsAreEnabled = false
    #expect(layout.seam.copyButtons.allSatisfy { !$0.isEnabled })
    layout.right.documentView.scroll(CGPoint(x: 0, y: layout.right.documentView.frame.height))
    layout.seam.layoutSubtreeIfNeeded()
    #expect(layout.seam.copyButtons.allSatisfy { !$0.isEnabled }, "new buttons too")
    layout.seam.copyButtonsAreEnabled = true
    #expect(layout.seam.copyButtons.allSatisfy { $0.isEnabled })
  }

  @Test func seamWithoutBandsDrawsNoneButKeepsItsButtons() throws {
    let (layout, window) = hosted([.toRight])
    defer { window.close() }
    #expect(!layout.seam.bands.isEmpty)
    layout.seam.showsBands = false
    layout.seam.layoutSubtreeIfNeeded()
    #expect(layout.seam.bands.isEmpty)
    #expect(!layout.seam.copyButtons.isEmpty)
  }
}

/// Records the presses of the buttons at a seam.
@MainActor
private final class SeamDelegate: PaneSeamDelegate {
  private(set) var presses: [(block: Int, direction: PaneSeam.CopyDirection)] = []

  func seam(_ seam: PaneSeam, didAskToCopyBlock block: Int, in direction: PaneSeam.CopyDirection) {
    presses.append((block, direction))
  }
}
