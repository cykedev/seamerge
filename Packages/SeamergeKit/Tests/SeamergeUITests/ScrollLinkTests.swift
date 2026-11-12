import AppKit
import MergeModel
import PaneKit
import Testing

@testable import SeamergeUI

/// The panes above and the result follow each other at their reading line, a quarter down.
@MainActor
@Suite struct ScrollLinkTests {
  @Test func scrollingTheResultBringsTheSameBlockToTheReadingLineAbove() async throws {
    let controller = try await windowWithManyBlocks()
    let result = try controller.mergeResult
    let blocks = result.content.blocks
    #expect(blocks.count > 40)
    #expect(result.collapsedRuns.isEmpty)
    for index in stride(from: 5, to: blocks.count - 10, by: 7) {
      let rows = blocks[index].rows
      let middle = (CGFloat(rows.lowerBound) + CGFloat(rows.count) / 2) * result.theme.rowHeight
      result.documentView.scroll(CGPoint(x: 0, y: middle - readingLine(of: result)))
      #expect(result.hit(at: CGPoint(x: 0, y: readingLine(of: result))).block == index)
      for (role, pane) in controller.layout.sourcePanes {
        let hit = pane.hit(at: CGPoint(x: 0, y: readingLine(of: pane)))
        #expect(hit.block == index, "pane \(role) at block \(index)")
      }
    }
  }

  @Test func scrollingASourceBringsTheSameBlockToTheReadingLineOfTheResult() async throws {
    let controller = try await windowWithManyBlocks()
    let a = try #require(controller.layout.sourcePane(.a))
    let blocks = a.content.blocks
    for index in stride(from: 3, to: blocks.count - 10, by: 9) {
      let rows = blocks[index].rows
      let middle = (CGFloat(rows.lowerBound) + CGFloat(rows.count) / 2) * a.theme.rowHeight
      a.documentView.scroll(CGPoint(x: 0, y: middle - readingLine(of: a)))
      let result = try controller.mergeResult
      #expect(result.hit(at: CGPoint(x: 0, y: readingLine(of: result))).block == index)
      let b = try #require(controller.layout.sourcePane(.b))
      #expect(b.hit(at: CGPoint(x: 0, y: readingLine(of: b))).block == index)
    }
  }

  @Test func blocksMeetAtTheReadingLineWithCollapsedRunsToo() async throws {
    let controller = try await windowWithManyBlocks(lineCount: 600, spacing: 30)
    let result = try controller.mergeResult
    #expect(!result.collapsedRuns.isEmpty)
    #expect(controller.layout.sourcePanes.allSatisfy { !$0.pane.collapsedRuns.isEmpty })
    let reading = readingLine(of: result)
    let height = result.documentView.frame.height
    var checked = Set<Int>()
    for y in stride(from: 0, to: height - result.bounds.height, by: result.theme.rowHeight / 3) {
      result.documentView.scroll(CGPoint(x: 0, y: y))
      // Only where the reading line lies well within a block, away from the rounding at its
      // edges.
      let blocks = [-3, 0, 3].map { result.hit(at: CGPoint(x: 0, y: reading + $0)).block }
      guard let block = blocks[1], blocks.allSatisfy({ $0 == block }) else { continue }
      // At the very end, a pane above whose text ends sooner stops at its last row instead.
      let followers = controller.layout.sourcePanes
      guard followers.allSatisfy({ !reachesItsEnd($0.pane) }) else { continue }
      checked.insert(block)
      for (role, pane) in followers {
        let hit = pane.hit(at: CGPoint(x: 0, y: readingLine(of: pane)))
        #expect(hit.block == block, "pane \(role) at block \(block), result at \(y)")
      }
    }
    // The first block lies above the reading line at the top, the last ones below it at the
    // end; every block between came to it.
    #expect(checked.isSuperset(of: 1..<result.content.blocks.count - 2))
  }

  /// A window at its standard size with the merge of many blocks.
  private func windowWithManyBlocks(
    lineCount: Int = 300, spacing: Int = 10
  ) async throws -> SessionWindowController {
    let session = try await SampleMerges.manyBlocks(lineCount: lineCount, spacing: spacing)
    return try Windows.controller(for: session)
  }

  /// Whether `pane` shows the end of its text, so that it cannot scroll further down.
  private func reachesItsEnd(_ pane: PaneView) -> Bool {
    let text = pane.documentView
    return text.visibleRect.maxY >= text.frame.height - 1
  }

  private func readingLine(of pane: PaneView) -> CGFloat {
    (pane.bounds.height * 0.25).rounded()
  }
}
