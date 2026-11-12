import AppKit
import PaneKit
import Testing

/// Measures a programmed pass through 100 000 rows in four coupled panes with overview bars:
/// scrolling, coupling and layout must stay within a frame at 60 Hz; the time to draw every part
/// of the panes is recorded with it.
///
/// Runs only in an optimized build: `swift test -c release -Xswiftc -enable-testing`.
@MainActor
@Suite struct ScrollingPerformanceTests {
  @Test(.enabled(if: Self.isOptimized))
  func passThroughOneHundredThousandRowsStaysWithinAFrame() throws {
    let rowCount = 100_000
    let blocks = stride(from: 25, to: rowCount, by: 50).map { row in
      PaneBlock(rows: row..<row + 3, style: .tinted(.a), marker: .changed)
    }
    let content = CodeRows.content(count: rowCount, length: 90, blocks: blocks)
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
    let sync = ScrollSync()
    let panes = (0..<4).map { index in
      let pane = PaneView()
      pane.content = content
      pane.frame =
        index < 3
        ? CGRect(x: CGFloat(index) * 427, y: 0, width: 426, height: 480)
        : CGRect(x: 0, y: 481, width: 1280, height: 319)
      host.addSubview(pane)
      sync.add(pane)
      return pane
    }
    let marks = blocks.enumerated().map { index, block in
      OverviewMark(
        rows: block.rows, style: .tinted(.a), placement: .leading, block: index,
        accessibilityLabel: "")
    }
    for pane in [panes[2], panes[3]] {
      let bar = OverviewBar()
      bar.marks = marks
      pane.overviewBar = bar
    }
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    // Every part of a pane draws into a layer of its own on screen; each draws into a bitmap of
    // its own here.
    let parts = panes.flatMap(\.subviews)
    let bitmaps = try parts.map { try #require($0.bitmapImageRepForCachingDisplay(in: $0.bounds)) }
    let leader = panes[0].documentView
    let range = leader.frame.height - leader.visibleRect.height
    let clock = ContinuousClock()
    // The run loop empties the autorelease pool after every event; so does every frame here.
    func frame(scrollingTo point: CGPoint) -> (layout: Duration, drawing: Duration) {
      autoreleasepool { measuredFrame(scrollingTo: point) }
    }
    func measuredFrame(scrollingTo point: CGPoint) -> (layout: Duration, drawing: Duration) {
      let layout = clock.measure {
        leader.scroll(point)
        host.layoutSubtreeIfNeeded()
      }
      let drawing = clock.measure {
        for (part, bitmap) in zip(parts, bitmaps) {
          part.cacheDisplay(in: part.bounds, to: bitmap)
        }
      }
      return (layout, drawing)
    }
    // A fast flick: a whole screen of new rows in every frame, so that every pane lays out and
    // draws all it shows, through the whole text.
    var flick: [(layout: Duration, drawing: Duration)] = []
    var y: CGFloat = 0
    while y < range {
      y = min(y + leader.visibleRect.height, range)
      flick.append(frame(scrollingTo: CGPoint(x: CGFloat(flick.count % 40), y: y)))
    }
    // Dragging the knob of the overview bar: a sixtieth of the text in every frame.
    let drag = (0...60).map { step in
      frame(scrollingTo: CGPoint(x: 0, y: (range * CGFloat(step) / 60).rounded()))
    }
    let summary = [
      "4 coupled panes of \(rowCount) rows with overview bars, 1280 × 800 pt",
      Self.summary(of: flick.map(\.layout), named: "flick, a screen per frame, scroll and layout"),
      Self.summary(of: flick.map(\.drawing), named: "flick, drawing"),
      Self.summary(of: flick.map { $0.layout + $0.drawing }, named: "flick, whole frame"),
      Self.summary(of: drag.map(\.layout), named: "knob drag, scroll and layout"),
      Self.summary(of: drag.map { $0.layout + $0.drawing }, named: "knob drag, whole frame"),
    ].joined(separator: "\n")
    try Rendering.writeText(summary, named: "scrolling-measurement")
    // Drawing into bitmaps renders in software what the screen composes from layers, so only
    // scrolling, coupling and layout are held to a frame; the drawing is recorded beside them.
    let layouts = flick.map(\.layout).sorted()
    #expect(layouts[layouts.count * 95 / 100] < .milliseconds(16), "\(summary)")
  }

  /// The number, median, 95th percentile and longest of `durations`, in milliseconds.
  private static func summary(of durations: [Duration], named name: String) -> String {
    let sorted = durations.sorted()
    func milliseconds(_ duration: Duration) -> String {
      String(format: "%.1f ms", Double(duration.components.attoseconds) / 1e15)
    }
    return
      "\(name): \(sorted.count) frames, median \(milliseconds(sorted[sorted.count / 2])), "
      + "95th percentile \(milliseconds(sorted[sorted.count * 95 / 100])), "
      + "longest \(milliseconds(sorted[sorted.count - 1]))"
  }

  nonisolated private static let isOptimized: Bool = {
    #if DEBUG
      false
    #else
      true
    #endif
  }()
}
