import AppKit
import Testing

@testable import PaneKit

/// Checks that the signs of the bar of toggles look centered in it: the letters, the ring of the
/// base and the trash can of a side that removed the lines leave as much room above as below,
/// off, taken by the merge and chosen alike, and stand in the middle of their segments; and that
/// the trash can is as high as the capitals beside it.
@MainActor
@Suite struct DecisionToggleCenteringTests {
  /// Where the parts of a row stand for the rows of the standard theme.
  static var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: Theme())
  }

  @Test(arguments: [
    BlockDecision.State.automatic([.a]), .chosen([.a, .base, .b]), .open, .chosen([.b]),
  ])
  func signsSitInTheMiddleOfTheirSegments(state: BlockDecision.State) throws {
    let removesLines = state == .chosen([.b])
    let toggles = [ColorRole.a, .base, .b].map { role in
      DecisionToggle(
        roles: [role], isOn: Self.isOn(role, in: state), isDeletion: removesLines && role == .b,
        help: "")
    }
    let row = DecisionRow(
      block: 0, theme: Theme(), toggleAction: (NSObject(), #selector(NSObject.description)),
      resetAction: (NSObject(), #selector(NSObject.description)))
    row.show(BlockDecision(state: state, toggles: toggles), place: "")
    let size = CGSize(width: Self.layout.rowWidth, height: Self.layout.height)
    let window = Rendering.host(row, size: size, appearance: NSAppearance(named: .aqua))
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: row)
    let bar = Self.layout.barRect
    var inks: [DecisionColumnLayout.Slot: Range<CGFloat>] = [:]
    for slot in [DecisionColumnLayout.Slot.a, .base, .b] {
      let frame = Self.layout.frame(of: slot)
      let ink = try Self.ink(in: bitmap, within: frame, bar: bar)
      inks[slot] = ink.rows
      let above = ink.rows.lowerBound - bar.minY
      let below = bar.maxY - ink.rows.upperBound
      #expect(abs(above - below) <= 0.5, "\(slot) in \(state): \(above) above, \(below) below")
      let left = ink.columns.lowerBound - frame.minX
      let right = frame.maxX - ink.columns.upperBound
      #expect(abs(left - right) <= 1, "\(slot) in \(state): \(left) left, \(right) right")
    }
    // The trash can of B stands as high as the capital A beside it, and on the same middle.
    if removesLines, let trash = inks[.b], let letter = inks[.a] {
      let trashHeight = trash.upperBound - trash.lowerBound
      let letterHeight = letter.upperBound - letter.lowerBound
      #expect(abs(trashHeight - letterHeight) <= 0.5, "trash \(trashHeight), A \(letterHeight)")
      let middles = (
        (trash.lowerBound + trash.upperBound) / 2, (letter.lowerBound + letter.upperBound) / 2
      )
      #expect(abs(middles.0 - middles.1) <= 0.5, "trash at \(middles.0), A at \(middles.1)")
    }
  }

  private static func isOn(_ role: ColorRole, in state: BlockDecision.State) -> Bool {
    switch state {
    case .automatic(let roles), .chosen(let roles): roles.contains(role)
    default: false
    }
  }

  /// The rows and columns of `bitmap` within the segment `frame` of `bar` whose color differs
  /// from the face of the segment, away from the outline of the bar and the hairlines between
  /// the segments.
  private static func ink(
    in bitmap: NSBitmapImageRep, within frame: CGRect, bar: CGRect
  ) throws -> (rows: Range<CGFloat>, columns: Range<CGFloat>) {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    func color(at point: CGPoint) throws -> NSColor {
      Contrast.over(try Rendering.color(in: bitmap, at: point), .white)
    }
    let margin = Theme.openConflictOutlineWidth + 2 / scale
    let face = try color(at: CGPoint(x: frame.midX, y: bar.minY + margin))
    var rows: [CGFloat] = []
    var columns: [CGFloat] = []
    // The rows of the sign in a strip down the middle of the segment, and its columns in a strip
    // across the middle of the bar, where neither meets the outline of the bar.
    let middleColumns = (frame.midX - 3)...(frame.midX + 3)
    let middleRows = (bar.midY - 2)...(bar.midY + 2)
    for y in stride(from: bar.minY + margin, to: bar.maxY - margin, by: 1 / scale) {
      for x in stride(from: frame.minX + margin, to: frame.maxX - margin, by: 1 / scale) {
        let color = try color(at: CGPoint(x: x, y: y))
        let distance =
          abs(color.redComponent - face.redComponent)
          + abs(color.greenComponent - face.greenComponent)
          + abs(color.blueComponent - face.blueComponent)
        // The sign of a toggle that is off is quiet, and thin lines are fainter where smoothed.
        guard distance > 0.4 else { continue }
        if middleColumns ~= x {
          rows.append(y)
        }
        if middleRows ~= y {
          columns.append(x)
        }
      }
    }
    let top = try #require(rows.min())
    let bottom = try #require(rows.max())
    let leading = try #require(columns.min())
    let trailing = try #require(columns.max())
    return (top..<bottom + 1 / scale, leading..<trailing + 1 / scale)
  }
}
