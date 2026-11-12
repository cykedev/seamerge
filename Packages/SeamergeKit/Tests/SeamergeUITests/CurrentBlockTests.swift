import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The current block: the same in every pane and both overview bars, made current by a click on
/// it anywhere, and brought into view in the other area only where it is not in full view.
@MainActor
@Suite struct CurrentBlockTests {
  @Test func windowOpensWithTheFirstOpenConflictCurrentInEveryPane() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.helloWorld())
    let presentation = controller.presentation
    let conflict = try #require(presentation.navigation.firstOpenConflict)
    #expect(presentation.currentBlock == conflict)
    for pane in Windows.panes(of: controller) {
      #expect(pane.currentBlock == conflict)
    }
    #expect(presentation.sourcesOverviewBar.currentBlock == conflict)
    #expect(try presentation.mergeResultOverviewBar.currentBlock == conflict)
  }

  @Test func windowWithoutConflictsOpensWithTheFirstChangeCurrent() async throws {
    let session = try await SampleMerges.TouchingBlocks.changeThenBoth.session()
    let controller = try Windows.controller(for: session)
    #expect(controller.presentation.navigation.openConflictCount == 0)
    #expect(controller.presentation.currentBlock == 0)
  }

  @Test func windowOpensWithItsFirstConflictInView() async throws {
    let lines = (1...400).map { "line \($0)" }
    var a = lines
    var b = lines
    a[300] += " from A"
    b[300] += " from B"
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    let session = try await SampleMerges.merge(
      base: text(lines), a: text(a), b: text(b))
    let controller = try Windows.controller(for: session)
    let block = try #require(controller.presentation.currentBlock)
    for pane in Windows.panes(of: controller) {
      #expect(pane.showsWhole(rows: pane.content.blocks[block].rows))
    }
  }

  @Test func clickOnAChangedRowInAnyPaneMakesItsBlockCurrentAndKeepsTheSelection() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    for (index, pane) in Windows.panes(of: controller).enumerated() {
      let block = 2 + index
      let selection = NSRange(location: 3, length: 4)
      pane.documentView.setSelectedRange(selection)
      let hit = pane.hit(at: Windows.point(inBlock: block, of: pane))
      #expect(hit.block == block)
      pane.delegate?.pane(pane, didClick: hit)
      #expect(controller.presentation.currentBlock == block)
      #expect(Windows.panes(of: controller).allSatisfy { $0.currentBlock == block })
      #expect(pane.documentView.selectedRange() == selection)
    }
  }

  @Test func clickInTheGutterMakesTheBlockOfItsRowCurrent() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let pane = try #require(controller.layout.sourcePane(.base))
    let block = 3
    let point = Windows.point(inBlock: block, of: pane)
    let gutter = try #require(
      pane.hitTest(pane.convert(CGPoint(x: 2, y: point.y), to: pane.superview)))
    #expect(!(gutter is NSTextView))
    gutter.mouseDown(with: try mouseDown(at: CGPoint(x: 2, y: point.y), in: pane))
    #expect(controller.presentation.currentBlock == block)
  }

  @Test func clickOnAMarkOfEitherOverviewBarMakesItsBlockCurrent() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let presentation = controller.presentation
    let bars = [
      (presentation.sourcesOverviewBar, 5), (try presentation.mergeResultOverviewBar, 7),
    ]
    for (bar, block) in bars {
      let marks = try #require(bar.accessibilityChildren() as? [NSAccessibilityElement])
      let index = try #require(bar.marks.firstIndex { $0.block == block })
      #expect(marks[index].accessibilityPerformPress())
      #expect(presentation.currentBlock == block)
    }
  }

  @Test func clickInTheDecisionColumnMakesTheBlockBesideItCurrent() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let result = try controller.mergeResult
    let column = try controller.presentation.mergeDecisionColumn
    let block = 4
    let point = result.convert(Windows.point(inBlock: block, of: result), to: column)
    column.mouseDown(with: try mouseDown(at: CGPoint(x: 2, y: point.y), in: column))
    #expect(controller.presentation.currentBlock == block)
  }

  @Test func clickOnAnUnchangedRowLeavesTheCurrentBlockAsItIs() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let current = controller.presentation.currentBlock
    for pane in Windows.panes(of: controller) {
      let hit = pane.hit(at: CGPoint(x: 8, y: 2))
      #expect(hit.block == nil)
      pane.delegate?.pane(pane, didClick: hit)
      #expect(controller.presentation.currentBlock == current)
    }
  }

  @Test func clickScrollsTheOtherAreaOnlyWhereTheBlockIsNotInFullView() async throws {
    let controller = try Windows.controller(for: try await SampleMerges.manyBlocks())
    let a = try #require(controller.layout.sourcePane(.a))
    let result = try controller.mergeResult
    let blocks = a.content.blocks.indices
    // In the result, which is lower than the panes above, a block low in A lies out of view.
    let inBoth = try #require(
      blocks.first { block in
        a.showsWhole(rows: a.content.blocks[block].rows)
          && result.showsWhole(rows: result.content.blocks[block].rows) && block > 0
      })
    let onlyAbove = try #require(
      blocks.last { block in
        a.showsWhole(rows: a.content.blocks[block].rows)
          && !result.showsWhole(rows: result.content.blocks[block].rows)
      })

    let offsets = Windows.panes(of: controller).map(Windows.scrollOffset(of:))
    a.delegate?.pane(a, didClick: a.hit(at: Windows.point(inBlock: inBoth, of: a)))
    #expect(Windows.panes(of: controller).map(Windows.scrollOffset(of:)) == offsets)

    a.delegate?.pane(a, didClick: a.hit(at: Windows.point(inBlock: onlyAbove, of: a)))
    #expect(controller.presentation.currentBlock == onlyAbove)
    #expect(result.showsWhole(rows: result.content.blocks[onlyAbove].rows))
    let readingLine = (result.documentView.visibleRect.height * Theme.readingLine).rounded()
    let firstRow = result.content.blocks[onlyAbove].rows.lowerBound
    let top = CGFloat(firstRow) * result.theme.rowHeight - Windows.scrollOffset(of: result)
    #expect(abs(top - readingLine) <= 1)
  }

  private func mouseDown(at point: CGPoint, in view: NSView) throws -> NSEvent {
    let window = try #require(view.window)
    return try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1))
  }
}
