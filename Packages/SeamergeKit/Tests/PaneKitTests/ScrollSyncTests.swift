import AppKit
import PaneKit
import Testing

/// Checks that coupled panes stand where the pane that scrolls stands, vertically and sideways,
/// that no pane pushes back the pane that leads, and that a coupling lets go of its panes.
@MainActor
@Suite struct ScrollSyncTests {
  @Test func coupledPanesStandAtTheOriginOfThePaneThatScrolled() throws {
    let (layout, window) = Self.coupledLayout()
    defer { window.close() }
    let panes = layout.upperPanes
    panes[1].documentView.scroll(CGPoint(x: 37, y: 450))
    for (index, pane) in panes.enumerated() {
      #expect(pane.documentView.visibleRect.origin == CGPoint(x: 37, y: 450), "pane \(index)")
    }
    #expect(layout.resultPane.documentView.visibleRect.minX == 37)
  }

  @Test func panesFollowWhicheverPaneScrollsLastAlsoWhenTheLeaderChangesQuickly() throws {
    let (layout, window) = Self.coupledLayout()
    defer { window.close() }
    let panes = layout.upperPanes
    var generator = SplitMix64(seed: Self.seed)
    let maximum = CGPoint(
      x: panes[0].documentView.frame.width - panes[0].documentView.visibleRect.width,
      y: panes[0].documentView.frame.height - panes[0].documentView.visibleRect.height)
    for step in 0..<200 {
      let leader = Int.random(in: 0..<panes.count, using: &generator)
      let target = CGPoint(
        x: CGFloat(Int.random(in: 0...Int(maximum.x), using: &generator)),
        y: CGFloat(Int.random(in: 0...Int(maximum.y), using: &generator)))
      panes[leader].documentView.scroll(target)
      for (index, pane) in panes.enumerated() {
        #expect(
          pane.documentView.visibleRect.origin == target,
          "seed \(Self.seed), step \(step), leader \(leader), pane \(index)")
      }
    }
  }

  @Test func paneThatScrollsIsNotMovedBackByThePanesThatFollow() throws {
    let (layout, window) = Self.coupledLayout()
    defer { window.close() }
    let leader = layout.upperPanes[0]
    let clipView = try #require(leader.documentView.enclosingScrollView?.contentView)
    var origins: [CGPoint] = []
    let observer = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil
    ) { _ in
      MainActor.assumeIsolated { origins.append(clipView.bounds.origin) }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    leader.documentView.scroll(CGPoint(x: 12, y: 300))
    layout.resultPane.documentView.scroll(CGPoint(x: 20, y: 100))
    let resultLeads = leader.documentView.visibleRect.origin
    layout.upperPanes[2].documentView.scroll(CGPoint(x: 0, y: 60))
    #expect(origins.first == CGPoint(x: 12, y: 300))
    #expect(origins.count == 3, "one change for each pane that led: \(origins)")
    #expect(resultLeads.x == 20)
  }

  @Test func panesBounceSidewaysTogetherBeyondEitherEdge() throws {
    let (layout, window) = Self.coupledLayout()
    defer { window.close() }
    let leader = layout.upperPanes[0]
    let clipView = try #require(leader.documentView.enclosingScrollView?.contentView)
    let range = leader.documentView.frame.width - clipView.bounds.width
    // The scroll view moves the clip view beyond the edge while it bounces.
    for x in [-24, range + 24] {
      clipView.scroll(to: CGPoint(x: x, y: 120))
      for pane in layout.upperPanes + [layout.resultPane] {
        #expect(pane.documentView.visibleRect.minX == x)
      }
    }
    clipView.scroll(to: CGPoint(x: -24, y: 120))
    try Rendering.write(Rendering.bitmap(of: layout), named: "bounce-sideways-light")
  }

  @Test func everyPaneScrollsAsFarSidewaysAsTheWidestText() throws {
    let theme = Theme()
    let short = PaneView(theme: theme)
    short.content = CodeRows.content(count: 50, length: 20)
    let long = PaneView(theme: theme)
    long.content = CodeRows.content(count: 50, length: 200)
    let wide = PaneView(theme: theme)
    wide.content = CodeRows.content(count: 30, length: 60)
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 400))
    short.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
    long.frame = CGRect(x: 300, y: 0, width: 300, height: 200)
    wide.frame = CGRect(x: 0, y: 200, width: 1000, height: 200)
    let sync = ScrollSync()
    for pane in [short, long, wide] {
      host.addSubview(pane)
      sync.add(pane)
    }
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let ranges = [short, long, wide].map {
      $0.documentView.frame.width - $0.documentView.visibleRect.width
    }
    #expect(Set(ranges).count == 1, "ranges \(ranges)")
    short.documentView.scroll(CGPoint(x: ranges[0], y: 0))
    for pane in [short, long, wide] {
      #expect(pane.documentView.visibleRect.minX == ranges[0])
    }
  }

  @Test(arguments: WholePixels.scrollerStyles)
  func resultFollowsTheUpperPanesBlockByBlockAtItsReadingLine(style: NSScroller.Style) throws {
    let theme = Theme()
    let upper = PaneView(theme: theme)
    upper.content = CodeRows.content(count: 400)
    let result = PaneView(theme: theme)
    result.content = CodeRows.content(count: 200)
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    upper.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    result.frame = CGRect(x: 0, y: 200, width: 400, height: 160)
    let sync = ScrollSync()
    for pane in [upper, result] {
      host.addSubview(pane)
      sync.add(pane)
    }
    sync.setRowMapping(between: upper, and: result, forward: { $0 / 2 }, backward: { $0 * 2 })
    let scale: CGFloat = 2
    let window = Rendering.host(host, size: host.frame.size, scale: scale)
    defer { window.close() }
    for pane in [upper, result] {
      pane.setScrollerStyle(style)
    }
    let rowHeight = theme.rowHeight
    upper.documentView.scroll(CGPoint(x: 0, y: 100 * rowHeight))
    // Row 100 plus a quarter of the visible height lies at the reading line of the upper pane;
    // the result stands at the whole pixel nearest to the place that brings half of it there.
    let upperRow = Self.readingLineRow(of: upper)
    let resultOrigin = result.documentView.visibleRect.minY
    let resultPlace = Self.origin(of: result, at: upperRow / 2)
    #expect(
      WholePixels.isNearest(resultOrigin, to: resultPlace, scale: scale),
      "\(resultOrigin) for \(resultPlace)")
    result.documentView.scroll(CGPoint(x: 0, y: 40 * rowHeight))
    let resultRow = Self.readingLineRow(of: result)
    let upperOrigin = upper.documentView.visibleRect.minY
    let upperPlace = Self.origin(of: upper, at: resultRow * 2)
    #expect(
      WholePixels.isNearest(upperOrigin, to: upperPlace, scale: scale),
      "\(upperOrigin) for \(upperPlace)")
  }

  @Test func panesWhoseMappingEndedTakeEachOthersOrigin() throws {
    let theme = Theme()
    let upper = PaneView(theme: theme)
    upper.content = CodeRows.content(count: 400)
    let result = PaneView(theme: theme)
    result.content = CodeRows.content(count: 400)
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    upper.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    result.frame = CGRect(x: 0, y: 200, width: 400, height: 200)
    let sync = ScrollSync()
    for pane in [upper, result] {
      host.addSubview(pane)
      sync.add(pane)
    }
    sync.setRowMapping(between: upper, and: result, forward: { $0 / 2 }, backward: { $0 * 2 })
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    sync.removeRowMapping(between: result, and: upper)
    for (leader, follower) in [(upper, result), (result, upper)] {
      leader.documentView.scroll(CGPoint(x: 0, y: 30 * theme.rowHeight))
      #expect(follower.documentView.visibleRect.minY == 30 * theme.rowHeight)
      leader.documentView.scroll(CGPoint(x: 0, y: 0))
    }
  }

  @Test func panesScrollOnTheirOwnWhileTheCouplingIsOffAndAlignWhenItIsOn() throws {
    let (layout, window) = Self.coupledLayout()
    defer { window.close() }
    layout.sync.isEnabled = false
    layout.upperPanes[0].documentView.scroll(CGPoint(x: 10, y: 200))
    #expect(layout.upperPanes[1].documentView.visibleRect.origin == .zero)
    layout.upperPanes[2].documentView.scroll(CGPoint(x: 30, y: 260))
    layout.sync.isEnabled = true
    // Turned on, the coupling brings the others to the pane that scrolled last.
    for pane in layout.upperPanes {
      #expect(pane.documentView.visibleRect.origin == CGPoint(x: 30, y: 260))
    }
    #expect(layout.resultPane.documentView.visibleRect.minX == 30)
    layout.upperPanes[1].documentView.scroll(CGPoint(x: 0, y: 80))
    #expect(layout.upperPanes[0].documentView.visibleRect.origin == CGPoint(x: 0, y: 80))
  }

  @Test func removedPanesAndAReleasedCouplingNoLongerFollow() throws {
    let theme = Theme()
    let panes = (0..<3).map { _ in
      let pane = PaneView(theme: theme)
      pane.content = CodeRows.content(count: 300)
      pane.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
      return pane
    }
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 200))
    for (index, pane) in panes.enumerated() {
      pane.frame.origin.x = CGFloat(index) * 300
      host.addSubview(pane)
    }
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    weak var released: ScrollSync?
    do {
      let sync = ScrollSync()
      released = sync
      for pane in panes {
        sync.add(pane)
      }
      sync.remove(panes[2])
      panes[0].documentView.scroll(CGPoint(x: 0, y: 100))
      #expect(panes[1].documentView.visibleRect.minY == 100)
      #expect(panes[2].documentView.visibleRect.minY == 0, "a removed pane stays")
    }
    #expect(released == nil, "the panes do not keep their coupling alive")
    panes[0].documentView.scroll(CGPoint(x: 0, y: 200))
    #expect(panes[1].documentView.visibleRect.minY == 100, "a released coupling lets go")
  }

  @Test func coupledPaneThatGoesAwayLeavesTheOthersCoupled() throws {
    let theme = Theme()
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 200))
    let window = Rendering.host(host, size: host.frame.size)
    defer { window.close() }
    let sync = ScrollSync()
    let kept = (0..<2).map { index in
      let pane = PaneView(theme: theme)
      pane.content = CodeRows.content(count: 300)
      pane.frame = CGRect(x: CGFloat(index) * 300, y: 0, width: 300, height: 200)
      host.addSubview(pane)
      sync.add(pane)
      return pane
    }
    weak var gone: PaneView?
    // AppKit hands out views autoreleased; the pool lets the pane go before the check.
    autoreleasepool {
      let pane = PaneView(theme: theme)
      pane.content = CodeRows.content(count: 300)
      host.addSubview(pane)
      sync.add(pane)
      gone = pane
      pane.removeFromSuperview()
    }
    #expect(gone == nil)
    host.layoutSubtreeIfNeeded()
    kept[0].documentView.scroll(CGPoint(x: 0, y: 140))
    #expect(kept[1].documentView.visibleRect.minY == 140)
  }

  @Test func gutterStaysWhileTheTextScrollsSideways() throws {
    let pane = PaneView()
    pane.content = CodeRows.content(count: 20, length: 200)
    let window = Rendering.host(pane, size: CGSize(width: 400, height: 200))
    defer { window.close() }
    let gutterWidth = pane.bounds.width - pane.documentView.visibleRect.width
    let before = try Rendering.bitmap(of: pane)
    pane.documentView.scroll(CGPoint(x: 300, y: 0))
    let after = try Rendering.bitmap(of: pane)
    var gutterChanged = false
    var textChanged = false
    for y in stride(from: 1, to: 199, by: 3) {
      for x in stride(from: 1, to: 399, by: 2) {
        let point = CGPoint(x: x, y: y)
        let same =
          try Rendering.color(in: before, at: point) == Rendering.color(in: after, at: point)
        if CGFloat(x) < gutterWidth {
          gutterChanged = gutterChanged || !same
        } else {
          textChanged = textChanged || !same
        }
      }
    }
    #expect(!gutterChanged)
    #expect(textChanged)
  }

  /// The row, with its fraction, at the reading line of `pane`, a quarter down its visible part.
  ///
  /// The origin and height are read from the pane, not assumed: a horizontal scroller in the
  /// legacy style, which the system may switch to while the tests run, takes height from the
  /// text, and AppKit aligns the origin that a pane scrolls to with the pixels of the screen.
  private static func readingLineRow(of pane: PaneView) -> CGFloat {
    let visible = pane.documentView.visibleRect
    return (visible.minY + 0.25 * visible.height) / pane.theme.rowHeight
  }

  /// The vertical origin at which `pane` has `row`, with its fraction, at its reading line.
  private static func origin(of pane: PaneView, at row: CGFloat) -> CGFloat {
    row * pane.theme.rowHeight - 0.25 * pane.documentView.visibleRect.height
  }

  /// The start value of the random scroll sequence; printed with every failure.
  private static let seed: UInt64 = 0x5EA_3E26

  private static func coupledLayout() -> (CoupledLayout, NSWindow) {
    let layout = CoupledLayout(merge: .transcoder, repeats: 12, theme: Theme())
    let window = Rendering.host(layout, size: CGSize(width: 1200, height: 700))
    return (layout, window)
  }
}
