import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// The edges of the bands of a seam meet the hairlines of the blocks in the panes on the same
/// pixel of the screen: at the top and the bottom of a block and at the point of a wedge, on
/// both sides of the seam, with the base and without, in both arrangements of the lines, at one
/// and two pixels per point, however far the panes are scrolled.
///
/// Drawn without a screen, a pane scrolled by a fraction of a pixel draws its hairlines there,
/// where the seam draws its edges; on a screen, the text shows at a whole pixel, and the edges
/// miss the hairlines. So the tests check first that the text of every pane lies on whole
/// pixels of the window, however it scrolls, and then, on the pictures, that edge and hairline
/// share a pixel row.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct SeamPixelTests {
  /// A window of panes: at a scale, with the base or without, with the lines lined up or not.
  struct Setup: Sendable, CustomTestStringConvertible {
    var scale: CGFloat
    var showsBase: Bool
    var alignsLines: Bool

    static let all = [1.0, 2.0].flatMap { scale in
      [true, false].flatMap { showsBase in
        [true, false].map { Setup(scale: scale, showsBase: showsBase, alignsLines: $0) }
      }
    }

    var testDescription: String {
      "\(Int(scale))x, base \(showsBase ? "shown" : "hidden"), "
        + (alignsLines ? "aligned" : "connected")
    }
  }

  @Test(arguments: Setup.all)
  func bandEdgesMeetTheHairlinesOfThePanesOnTheSamePixel(setup: Setup) async throws {
    let (controller, window) = try await Self.window(setup)
    defer { window.close() }
    let b = try #require(controller.layout.sourcePane(.b))
    var ends = (tops: 0, bottoms: 0, points: 0)
    for offset in [0, 13.37, 27.6, -5.125] {
      // Scrolled on by a fraction of a pixel, as the coupled panes scroll one another.
      b.scroll(to: CGPoint(x: 0, y: b.scrollOrigin.y + offset))
      window.contentView?.layoutSubtreeIfNeeded()
      let bitmap = try Rendering.bitmap(of: window)
      // Making their layers while the bitmap is drawn, the text views have not moved.
      Self.expectTextOnWholePixels(controller, "\(setup), scrolled by \(offset)")
      let found = try Self.expectEdgesOnHairlines(controller, in: bitmap, "\(setup), \(offset)")
      ends.tops += found.tops
      ends.bottoms += found.bottoms
      ends.points += found.points
      if setup.alignsLines {
        // On the grid, the rows of the panes side by side meet across the seams, which draw
        // no bands, when the panes share one origin.
        let origins = controller.layout.sourcePanes.filter(\.pane.isShown).map(\.pane.scrollOrigin)
        #expect(Set(origins.map(\.y)).count == 1, "\(setup), scrolled by \(offset): \(origins)")
      }
    }
    if !setup.alignsLines {
      #expect(ends.tops > 4 && ends.bottoms > 4 && ends.points > 0, "\(ends)")
    }
  }

  @Test(arguments: [1.0, 2.0])
  func panesScrolledByHandStopOnWholePixelsWithinTheirText(scale: CGFloat) async throws {
    let (controller, window) = try await Self.window(
      Setup(scale: scale, showsBase: true, alignsLines: false))
    defer { window.close() }
    let pixel = 1 / scale
    for (_, pane) in controller.layout.sourcePanes {
      let clip = pane.clipView
      let textHeight = pane.documentView.frame.height
      let end = textHeight - clip.bounds.height
      for y in [0.3, 101.37, 517.6, end - 0.2, end + 3.7] {
        let bounds = clip.constrainBoundsRect(
          CGRect(origin: CGPoint(x: 0, y: y), size: clip.bounds.size))
        #expect(
          (bounds.minY * scale).rounded() == bounds.minY * scale,
          "\(y) constrained to \(bounds.minY)")
        #expect(bounds.maxY <= textHeight, "\(y) constrained to \(bounds.minY)")
        #expect(abs(bounds.minY - min(y, end)) < pixel, "\(y) constrained to \(bounds.minY)")
      }
    }
  }

  @Test func paneThatGlidesStaysOnWholePixelsAllTheWay() async throws {
    let (controller, window) = try await Self.window(
      Setup(scale: 2, showsBase: true, alignsLines: false))
    defer { window.close() }
    let b = try #require(controller.layout.sourcePane(.b))
    let start = b.scrollOrigin.y
    // A glide through `animator()` sets the origin of the bounds frame by frame, at fractions of
    // a pixel; it runs only on a screen that is not locked, so the frames are set here as the
    // animation sets them.
    for frame in 1...30 {
      let progress = CGFloat(frame) / 30
      b.clipView.setBoundsOrigin(CGPoint(x: 0, y: start + 211.37 * progress * progress))
      Self.expectTextOnWholePixels(controller, "frame \(frame)")
    }
    #expect(abs(b.scrollOrigin.y - (start + 211.37)) < 0.5)
  }

  @Test func panesOnTheGridStandTogetherOnWholePixelsAfterEveryScroll() async throws {
    let (controller, window) = try await Self.window(
      Setup(scale: 2, showsBase: true, alignsLines: true))
    defer { window.close() }
    let b = try #require(controller.layout.sourcePane(.b))
    for step in 1...24 {
      b.scroll(to: CGPoint(x: 0, y: b.scrollOrigin.y + 0.37 * CGFloat(step)))
      let origins = controller.layout.sourcePanes.map(\.pane.scrollOrigin)
      #expect(Set(origins.map(\.y)).count == 1, "step \(step): \(origins)")
      Self.expectTextOnWholePixels(controller, "step \(step)")
    }
  }

  @Test func panesMoveToWholePixelsOfAScreenOfAnotherScale() async throws {
    let (controller, window) = try await Self.window(
      Setup(scale: 2, showsBase: true, alignsLines: true))
    defer { window.close() }
    let b = try #require(controller.layout.sourcePane(.b))
    b.scroll(to: CGPoint(x: 0, y: b.scrollOrigin.y + 40.5))
    #expect(b.scrollOrigin.y.rounded() != b.scrollOrigin.y, "on a half point at two pixels")
    // The window moves to a screen of one pixel per point, and AppKit tells its views.
    window.scale = 1
    func tell(_ view: NSView) {
      view.viewDidChangeBackingProperties()
      view.subviews.forEach(tell)
    }
    try tell(#require(window.contentView))
    Self.expectTextOnWholePixels(controller, "at one pixel per point")
    let origins = controller.layout.sourcePanes.map(\.pane.scrollOrigin.y)
    #expect(Set(origins).count == 1, "\(origins)")
  }

  // MARK: - Helpers

  /// The window for `setup`, laid out at 1000 × 730 points, at a block that one side lacks.
  private static func window(
    _ setup: Setup
  ) async throws -> (SessionWindowController, ScaledSessionWindow) {
    let settings = UserSettings.private()
    settings.alignsLines = setup.alignsLines
    let window = ScaledSessionWindow()
    window.scale = setup.scale
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let controller = SessionWindowController(
      session: try await SampleMerges.example(), context: SessionContext(),
      undoManager: UndoManager(), displayOptions: DisplayOptions(reducesMotion: true),
      pasteboard: .withUniqueName(), workspace: WorkspaceRecorder(), prompts: PromptRecorder(),
      doneStyle: .standard, settings: settings, syntaxChoices: SyntaxChoices(), window: window,
      unavailable: nil)
    Rendering.prepare(
      window, size: CGSize(width: 1000, height: 730), appearance: .init(named: .aqua)!)
    controller.layout.placeDividers()
    if !setup.showsBase {
      controller.toggleBase(nil)
    }
    // A block in the second half that one side lacks, where the connected panes form a wedge.
    let blocks = controller.presentation.changes.blocks
    let insertion = blocks.indices.first { block in
      block >= blocks.count / 2
        && (blocks[block].lines(in: .a).isEmpty || blocks[block].lines(in: .b).isEmpty)
    }
    // The block after it is the current one, whose darker tint would hide the hairlines from
    // the search for the darkest row.
    controller.presentation.jump(to: (insertion ?? blocks.count / 2) + 1)
    window.contentView?.layoutSubtreeIfNeeded()
    return (controller, window)
  }

  /// Checks that the text of every pane in view stands at the origin of its clip view, with its
  /// top left corner on whole pixels of the window.
  private static func expectTextOnWholePixels(
    _ controller: SessionWindowController, _ context: String
  ) {
    let scale = controller.window?.backingScaleFactor ?? 2
    let layout = controller.layout
    let panes = layout.sourcePanes.map(\.pane) + [layout.resultPane].compactMap(\.self)
    for pane in panes where pane.isShown {
      #expect(pane.documentView.frame.origin == .zero, "\(context)")
      let corner = pane.documentView.convert(CGPoint.zero, to: nil)
      #expect(
        (corner.x * scale).rounded() == corner.x * scale
          && (corner.y * scale).rounded() == corner.y * scale,
        "\(context): text at \(corner), scrolled to \(pane.scrollOrigin)")
    }
  }

  /// Checks on `bitmap` that each end of a band in view lies on the pixel row of the hairline
  /// of its pane, and returns how many tops, bottoms and points of wedges it checked.
  private static func expectEdgesOnHairlines(
    _ controller: SessionWindowController, in bitmap: NSBitmapImageRep, _ context: String
  ) throws -> (tops: Int, bottoms: Int, points: Int) {
    let window = try #require(controller.window)
    let frameView = try #require(window.contentView?.superview)
    let scale = CGFloat(bitmap.pixelsWide) / frameView.bounds.width
    try #require(scale == window.backingScaleFactor)
    /// The pixel column and the pixel row with its fraction of `point` in `view`.
    func pixel(of point: CGPoint, in view: NSView) -> (x: Int, y: CGFloat) {
      let inFrame = frameView.convert(point, from: view)
      return (Int(inFrame.x * scale), (frameView.bounds.height - inFrame.y) * scale)
    }
    /// The darkest pixel row in column `x` near row `y`: a hairline or an edge, which lie on
    /// lighter rows in the light appearance.
    func line(atColumn x: Int, near y: CGFloat) throws -> Int {
      let center = Int(y.rounded(.down))
      func brightness(_ row: Int) throws -> CGFloat {
        let color = try #require(bitmap.colorAt(x: x, y: row))
        return color.redComponent + color.greenComponent + color.blueComponent
      }
      var darkest = center
      for row in center - 3...center + 3 where try brightness(row) < brightness(darkest) {
        darkest = row
      }
      return darkest
    }
    var found = (tops: 0, bottoms: 0, points: 0)
    for seam in controller.layout.seams {
      let panes = try (#require(seam.leftPane), #require(seam.rightPane))
      for band in seam.bands {
        for (end, pane, isLeft) in [(band.left, panes.0, true), (band.right, panes.1, false)]
        where !band.isCurrent {
          let text = seam.convert(pane.clipView.bounds, from: pane.clipView)
          for y in Set([end.lowerBound, end.upperBound])
          where y > text.minY + 4 && y < text.maxY - 4 {
            // The edge in the second pixel column of the seam, next to its own hairline along
            // the pane, before a steep edge turns away.
            let edgeX = isLeft ? seam.bounds.minX + 1.5 / scale : seam.bounds.maxX - 1.5 / scale
            let edge = pixel(of: CGPoint(x: edgeX, y: y), in: seam)
            // The hairline in the inset before the text, where no mark of a word lies on it.
            let hairline = pixel(
              of: CGPoint(x: pane.clipView.bounds.minX + 2 / scale, y: 0), in: pane.clipView)
            // The edge, one pixel thick around `y`, covers a whole pixel row, as the hairline of
            // the pane does.
            let top = edge.y - 0.5
            #expect(top.rounded() == top, "\(context), block \(band.block) at \(y): \(top)")
            let edgeRow = try line(atColumn: edge.x, near: edge.y)
            let hairlineRow = try line(atColumn: hairline.x, near: edge.y)
            #expect(
              edgeRow == hairlineRow,
              """
              \(context), block \(band.block), \(isLeft ? "left" : "right") end at \(y), \
              pixel \(edge) beside \(hairline.x)
              """)
            if end.lowerBound == end.upperBound {
              found.points += 1
            } else if y == end.lowerBound {
              found.tops += 1
            } else {
              found.bottoms += 1
            }
          }
        }
      }
    }
    return found
  }
}

/// A session window on a screen of `scale` pixels per point, where a window without a screen
/// takes the scale of the main screen.
final class ScaledSessionWindow: SessionWindow {
  var scale: CGFloat = 2

  override var backingScaleFactor: CGFloat { scale }
}
