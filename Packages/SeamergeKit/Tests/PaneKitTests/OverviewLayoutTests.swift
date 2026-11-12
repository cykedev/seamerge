import CoreGraphics
import Testing

@testable import PaneKit

/// Checks where the marks of the overview bar lie and what a click at a height hits.
@Suite struct OverviewLayoutTests {
  private let area = CGRect(x: 2, y: 3, width: 8, height: 600)

  @Test func singleRowAmongOneHundredThousandGetsAMarkThatCanBeHit() {
    let layout = OverviewLayout(
      marks: [Self.mark(rows: 54_321..<54_322, .tinted(.a), .leading, block: 7)],
      rowCount: 100_000, area: area)
    let rect = layout.shapes[0].rect
    #expect(rect.height == 3)
    let middle = area.minY + 54_321.5 / 100_000 * area.height
    #expect(abs(rect.midY - middle) < 0.01)
    for y in [rect.minY - 2, rect.midY, rect.maxY + 2] {
      #expect(layout.block(at: y) == 7, "y \(y)")
    }
    #expect(layout.block(at: rect.minY - 10) == nil)
  }

  @Test func openConflictIsNeverCoveredByTheMarksAroundIt() {
    var marks: [OverviewMark] = []
    for row in stride(from: 40_000, to: 60_000, by: 10) {
      let isConflict = row == 50_000
      marks.append(
        Self.mark(
          rows: row..<row + 2, isConflict ? .tinted(.conflict) : .tinted(row % 20 == 0 ? .a : .b),
          isConflict ? .fullWidth : row % 20 == 0 ? .leading : .trailing, block: row))
    }
    let layout = OverviewLayout(marks: marks, rowCount: 100_000, area: area)
    let conflictIndex = layout.shapes.firstIndex(where: \.isOpenConflict)
    #expect(conflictIndex == layout.shapes.count - 1, "drawn last, above every other mark")
    let conflict = layout.shapes[layout.shapes.count - 1]
    #expect(conflict.members.map(\.block) == [50_000])
    #expect(conflict.rect.width == area.width)
    #expect(layout.block(at: conflict.rect.midY) == 50_000)
    #expect(layout.block(at: conflict.rect.minY - 1) == 50_000)
  }

  @Test func neighborsOfOneKindMergeWhereTheyTouchAndOtherKindsStayApart() {
    let layout = OverviewLayout(
      marks: [
        Self.mark(rows: 10..<11, .tinted(.a), .leading, block: 0),
        Self.mark(rows: 12..<13, .tinted(.a), .leading, block: 1),
        Self.mark(rows: 14..<15, .tinted(.b), .trailing, block: 2),
        Self.mark(rows: 90_000..<90_001, .tinted(.a), .leading, block: 3),
      ], rowCount: 100_000, area: area)
    #expect(layout.shapes.map { $0.members.map(\.block) } == [[0, 1], [2], [3]])
    #expect(layout.markRects.count == 4)
  }

  @Test func marksAtTheEndsStayWithinTheBar() {
    let layout = OverviewLayout(
      marks: [
        Self.mark(rows: 0..<1, .tinted(.a), .leading, block: 0),
        Self.mark(rows: 99_999..<100_000, .tinted(.b), .trailing, block: 1),
      ], rowCount: 100_000, area: area)
    #expect(layout.shapes[0].rect.minY == area.minY)
    #expect(layout.shapes[1].rect.maxY == area.maxY)
  }

  @Test func marksOfAAreLeadingOfBTrailingAndConflictsAcross() {
    let layout = OverviewLayout(
      marks: [
        Self.mark(rows: 0..<10, .tinted(.a), .leading, block: 0),
        Self.mark(rows: 20..<30, .tinted(.b), .trailing, block: 1),
        Self.mark(rows: 40..<50, .handwritten, .fullWidth, block: 2),
      ], rowCount: 100, area: area)
    let rects = layout.markRects
    #expect(rects[0].minX == area.minX && rects[0].maxX < area.maxX)
    #expect(rects[1].minX > area.minX && rects[1].maxX == area.maxX)
    #expect(rects[2].minX == area.minX && rects[2].maxX == area.maxX)
    #expect(abs(rects[0].width - area.width * 2 / 3) < 0.001)
  }

  private static func mark(
    rows: Range<Int>, _ style: BlockStyle, _ placement: OverviewMark.Placement, block: Int
  ) -> OverviewMark {
    OverviewMark(
      rows: rows, style: style, placement: placement, block: block, accessibilityLabel: "")
  }
}
