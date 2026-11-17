import AppKit
import Testing

@testable import PaneKit

/// Checks that the rows of the decision column make the images of their signs once: AppKit draws
/// them again at every step of scrolling, and only a new theme or appearance asks for new images.
@MainActor
@Suite struct SymbolImagesTests {
  @Test func drawingTheRowsAgainMakesNoImages() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane()
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    let arrows = Self.descendants(of: pane, as: ResetBlockButton.self)
    let caches = rows.map(\.symbols) + arrows.map(\.symbols)
    let views: [NSView] = rows + arrows
    Self.draw(views)
    let made = caches.map(\.madeCount)
    #expect(made.contains { $0 > 0 })
    for _ in 0..<3 {
      Self.draw(views)
    }
    #expect(caches.map(\.madeCount) == made)
  }

  @Test func anotherAppearanceMakesImagesOnceForItself() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane(
      appearance: NSAppearance(named: .aqua))
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    Self.draw(rows)
    let made = rows.map(\.symbols.madeCount)
    window.appearance = NSAppearance(named: .darkAqua)
    Self.draw(rows)
    let madeInDark = rows.map(\.symbols.madeCount)
    #expect(madeInDark.reduce(0, +) > made.reduce(0, +))
    window.appearance = NSAppearance(named: .aqua)
    Self.draw(rows)
    window.appearance = NSAppearance(named: .darkAqua)
    Self.draw(rows)
    #expect(rows.map(\.symbols.madeCount) == madeInDark)
  }

  @Test func aNewThemeMakesTheImagesAgain() throws {
    let (pane, _, window, _) = DecisionColumnTests.resultPane()
    defer { window.close() }
    let rows = Self.descendants(of: pane, as: DecisionRow.self)
    Self.draw(rows)
    let made = rows.map(\.symbols.madeCount)
    for row in rows {
      row.theme = Theme(
        font: .monospacedSystemFont(ofSize: 16, weight: .regular), increasesContrast: true)
    }
    Self.draw(rows)
    let madeAgain = zip(rows.map(\.symbols.madeCount), made).map { $0 - $1 }
    #expect(madeAgain == made)
  }

  private static func draw(_ views: [NSView]) {
    for view in views {
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
  }

  private static func descendants<View: NSView>(of view: NSView, as type: View.Type) -> [View] {
    view.subviews.flatMap { subview in
      [subview as? View].compactMap(\.self) + descendants(of: subview, as: type)
    }
  }
}
