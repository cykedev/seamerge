import AppKit
import Testing

@testable import PaneKit

/// The hairlines at the edges of changed blocks: where they are drawn, when they are strong, and
/// that they show against the rows on both sides in every look.
@MainActor
@Suite struct BlockEdgeTests {
  /// Two touching blocks without markers, an unchanged row, a block of B and an open conflict
  /// whose stacked preview of A and B is one block, as in the result.
  private static let result = PaneContent(
    text: (0..<9).map { "row \($0)" }.joined(separator: "\n"),
    lineNumbers: (0..<9).map(Int32.init),
    blocks: [
      PaneBlock(rows: 0..<2, style: .tinted(.a)),
      PaneBlock(rows: 2..<4, style: .combined),
      PaneBlock(rows: 5..<6, style: .tinted(.b)),
      PaneBlock(rows: 6..<8, style: .tinted(.conflict)),
    ],
    previews: [PanePreview(range: 36..<42, role: .a), PanePreview(range: 42..<48, role: .b)])

  /// Touching blocks of A with markers: twice the same tint, then a change of both in another.
  private static let side = PaneContent(
    text: (0..<6).map { "row \($0)" }.joined(separator: "\n"),
    lineNumbers: (0..<6).map(Int32.init),
    blocks: [
      PaneBlock(rows: 0..<2, style: .tinted(.a), marker: .changed),
      PaneBlock(rows: 2..<4, style: .tinted(.a), marker: .added),
      PaneBlock(rows: 4..<6, style: .unchanged),
    ])

  @Test func everyBlockHasAnEdgeAtItsTopAndItsBottomAndTouchingBlocksShareOne() throws {
    let edges = try edges(of: Self.result)
    #expect(edges.top == [0, 2, 5, 6])
    #expect(edges.bottom == [3, 7])
  }

  @Test func edgeIsStrongWhereNothingElseShowsTheBoundary() throws {
    // Without markers, every edge between two tinted blocks is the only boundary.
    #expect(try edges(of: Self.result).strongTop == [2, 6])
    // With markers, only the edge between two blocks of the same tint is; a pane that leaves
    // the block below untinted keeps the quiet edge.
    let side = try edges(of: Self.side)
    #expect(side.top == [0, 2, 4])
    #expect(side.strongTop == [2])
  }

  @Test func edgeBetweenTwoBlocksTakesTheTintThatStandsOutMore() throws {
    let theme = Theme()
    let appearance = try #require(NSAppearance(named: .aqua))
    let resolve = { (color: NSColor?) in Contrast.resolve(color, in: appearance) }
    let between = try #require(
      resolve(theme.edgeColor(between: .tinted(.a), and: .original, isOnlyBoundary: false)))
    let alone = try #require(
      resolve(theme.edgeColor(between: .tinted(.a), and: nil, isOnlyBoundary: false)))
    #expect(between == alone)
    #expect(theme.edgeColor(between: .unchanged, and: nil, isOnlyBoundary: false) == nil)
  }

  /// A hairline stays visible against the rows beside it.
  ///
  /// A quiet hairline needs 1.3 : 1: it adds to the tint and the marker rather than saying
  /// something alone, so it need not reach the 3 : 1 of signs, but it must stay visible as a
  /// line. Where it alone shows the boundary, it is a sign: 3 : 1.
  @Test(arguments: Look.all, [false, true])
  func edgeShowsAgainstTheRowsOnBothSides(look: Look, isOnlyBoundary: Bool) {
    let theme = Theme(increasesContrast: look.increasesContrast)
    let resolve = { (color: NSColor?) in Contrast.resolve(color, in: look.appearance) }
    let ground = Contrast.over(resolve(.textBackgroundColor), .white)
    let tinted: [BlockStyle] = [
      .tinted(.a), .tinted(.b), .tinted(.conflict), .original, .combined, .handwritten,
    ]
    let styles: [BlockStyle?] = isOnlyBoundary ? tinted : [nil, .unchanged] + tinted
    let minimum: CGFloat = isOnlyBoundary ? 3 : 1.3
    var failures: [String] = []
    for upper in styles {
      for lower in styles {
        guard
          let edge = resolve(
            theme.edgeColor(between: upper, and: lower, isOnlyBoundary: isOnlyBoundary))
        else { continue }
        for (side, style) in [("above", upper), ("below", lower)] {
          for isCurrent in [false, true] {
            for isFiller in [false, true] {
              let fill = style.flatMap {
                theme.rowFill(for: $0, isFiller: isFiller, isCurrent: isCurrent)
              }
              let ratio = Contrast.ratio(edge, Contrast.over(resolve(fill), ground))
              if ratio < minimum {
                failures.append(
                  "\(String(describing: upper)) | \(String(describing: lower)), \(side)"
                    + "\(isCurrent ? ", current" : "")\(isFiller ? ", filler" : ""): "
                    + String(format: "%.2f", ratio))
              }
            }
          }
        }
      }
    }
    #expect(failures.isEmpty, "\(failures.joined(separator: "; "))")
  }

  /// The rows whose top and whose bottom carry a hairline, and those whose top hairline is the
  /// strong one.
  private func edges(of content: PaneContent) throws -> (
    top: [Int], bottom: [Int], strongTop: [Int]
  ) {
    let pane = PaneView()
    pane.content = content
    let appearance = try #require(NSAppearance(named: .aqua))
    let edges = pane.textView.painting(forRows: 0..<content.lineNumbers.count).edges
    let strongTop = edges.indices.filter { row in
      guard let top = edges[row].top, row > 0 else { return false }
      let strong = pane.theme.edgeColor(
        between: pane.textView.style(ofRow: row - 1), and: pane.textView.style(ofRow: row),
        isOnlyBoundary: true)
      return Contrast.resolve(top, in: appearance) == Contrast.resolve(strong, in: appearance)
    }
    return (
      edges.indices.filter { edges[$0].top != nil },
      edges.indices.filter { edges[$0].bottom != nil },
      strongTop
    )
  }
}
