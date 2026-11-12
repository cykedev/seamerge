import AppKit
import PaneKit
import Testing

/// Checks what a pane reports about clicks and which context menu it shows.
@MainActor
@Suite struct InteractionTests {
  @Test func clickInTheGutterReportsItsRowAndBlock() throws {
    let (pane, window, delegate) = try Self.paneWithDelegate()
    defer { window.close() }
    pane.documentView.scroll(CGPoint(x: 0, y: pane.theme.rowHeight))
    // The gutter shows row 3 in its third slot after scrolling by a row.
    try Clicking.click(try Self.gutter(of: pane), at: CGPoint(x: 4, y: 2.5 * pane.theme.rowHeight))
    #expect(delegate.clicks == [PaneHit(row: 3, block: 0)])
  }

  @Test func secondaryClickShowsTheDelegatesMenuInsteadOfTheStandardOne() throws {
    let (pane, window, delegate) = try Self.paneWithDelegate()
    defer { window.close() }
    let point = CGPoint(x: 40, y: 3.5 * pane.theme.rowHeight)
    let menu = try Clicking.menu(of: pane.documentView, at: point)
    #expect(menu === delegate.menu)
    #expect(delegate.menuHits == [PaneHit(row: 3, block: 0)])
    let gutterMenu = try Clicking.menu(of: try Self.gutter(of: pane), at: point)
    #expect(gutterMenu === delegate.menu)
    #expect(delegate.menuHits.last == PaneHit(row: 3, block: 0))
  }

  @Test func paneWithoutDelegateKeepsTheStandardMenuOfTheText() throws {
    let pane = PaneView()
    pane.content = Self.content
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 200))
    defer { window.close() }
    let menu = try Clicking.menu(
      of: pane.documentView, at: CGPoint(x: 40, y: 0.5 * pane.theme.rowHeight))
    #expect(menu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true)
  }

  @Test func hitAtAPointNamesTheRowBelowItAfterScrolling() throws {
    let pane = PaneView()
    pane.content = Self.content
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 60))
    defer { window.close() }
    let rowHeight = pane.theme.rowHeight
    pane.documentView.scroll(CGPoint(x: 0, y: 2 * rowHeight))
    #expect(pane.hit(at: CGPoint(x: 100, y: 0.5 * rowHeight)) == PaneHit(row: 2, block: 0))
    #expect(pane.hit(at: CGPoint(x: 100, y: 1_000)) == PaneHit(row: 5, block: nil))
  }

  /// Six rows; rows 2 to 4 form block 0.
  private static let content = PaneContent(
    text: "zero\none\ntwo\nthree\nfour\nfive", lineNumbers: [0, 1, 2, 3, 4, 5],
    blocks: [PaneBlock(rows: 2..<5, style: .tinted(.a), marker: .changed)])

  private static func paneWithDelegate() throws -> (PaneView, NSWindow, Recorder) {
    let pane = PaneView()
    pane.content = content
    let recorder = Recorder()
    pane.delegate = recorder
    let window = Rendering.host(pane, size: CGSize(width: 300, height: 80))
    // The pane holds its delegate weakly; the test keeps it.
    return (pane, window, recorder)
  }

  private static func gutter(of pane: PaneView) throws -> NSView {
    try #require(pane.subviews.first { !($0 is NSScrollView) })
  }
}

/// Records what a pane reports and answers with one menu.
@MainActor
private final class Recorder: PaneViewDelegate {
  let menu = NSMenu()
  var clicks: [PaneHit] = []
  var menuHits: [PaneHit] = []
  var expandedRuns: [CollapsedRun] = []

  func pane(_ pane: PaneView, didClick hit: PaneHit) {
    clicks.append(hit)
  }

  func pane(_ pane: PaneView, menuFor hit: PaneHit) -> NSMenu? {
    menuHits.append(hit)
    return menu
  }

  func pane(_ pane: PaneView, didAskToExpand run: CollapsedRun) {
    expandedRuns.append(run)
  }

  func pane(_ pane: PaneView, didAskToCollapse run: CollapsedRun) {}
}
