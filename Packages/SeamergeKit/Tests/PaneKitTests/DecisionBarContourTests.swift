import AppKit
import Testing

@testable import PaneKit

/// Checks that the bar of toggles has the same contour in every state: off, taken by the merge,
/// chosen, edited and open, open also with marks that differ in shape, so that no bar looks
/// larger than another.
@MainActor
@Suite struct DecisionBarContourTests {
  /// Where the parts of a row stand for the rows of the standard theme.
  static var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: Theme())
  }

  @Test func everyStateDrawsTheSameContourToThePixel() throws {
    let states: [(String, BlockDecision, Theme)] = [
      ("off", Self.decision(.chosen([]), on: []), Theme()),
      ("taken by the merge", Self.decision(.automatic([.a]), on: [.a]), Theme()),
      ("chosen", Self.decision(.chosen([.a, .base, .b]), on: [.a, .base, .b]), Theme()),
      ("edited", Self.decision(.edited, on: [.b]), Theme()),
      ("open", Self.decision(.open, on: []), Theme()),
      ("open without color", Self.decision(.open, on: []), Theme(differentiatesWithoutColor: true)),
    ]
    var contours: [String: CGRect] = [:]
    for (name, decision, theme) in states {
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let row = DecisionRow(
          block: 0, theme: theme, toggleAction: (NSObject(), #selector(NSObject.description)),
          resetAction: (NSObject(), #selector(NSObject.description)))
        row.show(decision, place: "")
        let size = CGSize(width: Self.layout.rowWidth, height: Self.layout.height)
        let window = Rendering.host(row, size: size, appearance: NSAppearance(named: appearance))
        defer { window.close() }
        let bitmap = try Rendering.bitmap(of: row)
        try #require(bitmap.pixelsWide == 2 * Int(size.width), "The test draws at 2×")
        contours["\(name), \(appearance.rawValue)"] = Self.opaqueBounds(
          of: bitmap, within: Self.layout.barRect.insetBy(dx: -2, dy: -2))
      }
    }
    let expected = try #require(contours["off, \(NSAppearance.Name.aqua.rawValue)"])
    // The contour is the bar itself, nothing around it.
    let bar = Self.layout.barRect
    #expect(
      expected
        == CGRect(x: bar.minX * 2, y: bar.minY * 2, width: bar.width * 2, height: bar.height * 2))
    for (name, contour) in contours.sorted(by: { $0.key < $1.key }) {
      #expect(contour == expected, "\(name): \(contour), not \(expected)")
    }
  }

  private static func decision(_ state: BlockDecision.State, on: Set<ColorRole>) -> BlockDecision {
    BlockDecision(state: state, toggles: DecisionColumnTests.toggles(on: on))
  }

  /// The bounds in pixels of the pixels of `bitmap` within `rect` that are not transparent.
  private static func opaqueBounds(of bitmap: NSBitmapImageRep, within rect: CGRect) -> CGRect {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    var bounds = CGRect.null
    for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
      for x in Int(rect.minX * scale)..<Int(rect.maxX * scale)
      where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
        bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    return bounds
  }
}
