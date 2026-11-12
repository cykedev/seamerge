import AppKit
import Testing

@testable import PaneKit

/// Checks that the labels of the toggles look centered: their capitals, and the trash can of a
/// toggle that follows a deletion, leave as much room above as below, on and off alike; and that
/// the trash can is about as high as the capitals.
@MainActor
@Suite struct DecisionToggleCenteringTests {
  @Test(
    arguments: [
      ([ColorRole.a], true, false), ([.b], true, false), ([.a, .b], true, false),
      ([.b], true, true), ([.base], false, false), ([.base, .a], false, false),
      ([.b], false, true),
    ])
  func capitalsAndTrashCanSitInTheMiddleOfTheToggle(
    roles: [ColorRole], isOn: Bool, isDeletion: Bool
  ) throws {
    let toggle = DecisionToggle(roles: roles, isOn: isOn, isDeletion: isDeletion, help: "")
    let button = DecisionToggleButton(block: 0, index: 0, toggle: toggle, theme: Theme())
    let size = CGSize(
      width: DecisionToggleButton.width(of: toggle), height: Theme.decisionControlSize)
    let window = Rendering.host(button, size: size, appearance: NSAppearance(named: .aqua))
    defer { window.close() }
    let bitmap = try Rendering.bitmap(of: button)
    let label = NSAttributedString(
      string: DecisionToggleButton.label(of: toggle),
      attributes: [.font: DecisionToggleButton.font])
    let symbolWidth =
      isDeletion ? size.width - label.size().width - 2 * Theme.toggleLabelPadding : 0
    let labelStart = ((size.width - label.size().width - symbolWidth) / 2).rounded()
    let labelEnd = labelStart + label.size().width
    // The first letter is always a capital; lowercase letters overshoot the baseline.
    let capital = NSAttributedString(
      string: String(DecisionToggleButton.label(of: toggle).prefix(1)),
      attributes: [.font: DecisionToggleButton.font])
    let parts =
      [("capital", labelStart..<labelStart + capital.size().width)]
      + (isDeletion ? [("trash can", labelEnd + 1..<size.width - Theme.toggleLabelPadding)] : [])
    var heights: [CGFloat] = []
    for (name, xs) in parts {
      let ink = try Self.ink(in: bitmap, xs: xs, height: size.height)
      let above = ink.lowerBound
      let below = size.height - ink.upperBound
      #expect(abs(above - below) <= 0.5, "\(name) of \(roles): \(above) above, \(below) below")
      heights.append(ink.upperBound - ink.lowerBound)
    }
    // The trash can is no more than a point higher than the capital beside it.
    if heights.count == 2 {
      #expect(heights[1] <= heights[0] + 1, "trash can \(heights[1]), capital \(heights[0])")
    }
  }

  /// The rows of `bitmap` within `xs` whose color differs from the face of the toggle, from the
  /// top of the first to the bottom of the last.
  private static func ink(in bitmap: NSBitmapImageRep, xs: Range<CGFloat>, height: CGFloat)
    throws -> Range<CGFloat>
  {
    let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
    // A toggle that is off draws no face; the column behind it is the text background.
    func color(at point: CGPoint) throws -> NSColor {
      Contrast.over(try Rendering.color(in: bitmap, at: point), .white)
    }
    let face = try color(at: CGPoint(x: xs.lowerBound, y: 2))
    var rows: [CGFloat] = []
    for y in stride(from: 0, to: height, by: 1 / scale) {
      for x in stride(from: xs.lowerBound, to: xs.upperBound, by: 1 / scale) {
        let color = try color(at: CGPoint(x: x, y: y))
        let distance =
          abs(color.redComponent - face.redComponent)
          + abs(color.greenComponent - face.greenComponent)
          + abs(color.blueComponent - face.blueComponent)
        if distance > 0.9 {
          rows.append(y)
          break
        }
      }
    }
    let top = try #require(rows.first)
    let bottom = try #require(rows.last)
    return top..<bottom + 1 / scale
  }
}
