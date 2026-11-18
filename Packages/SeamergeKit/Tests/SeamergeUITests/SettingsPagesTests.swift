import AppKit
import Testing

@testable import SeamergeUI

/// The pages of the window Settings: the window goes over to the size of the page it turns to,
/// without passing it, and takes it at once with Reduce Motion; its top edge stays.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SettingsPagesTests {
  @Test func withReduceMotionTheWindowTakesTheSizeOfThePageAtOnce() throws {
    let controller = SettingsWindowController(
      settings: .private(), updates: nil, displayOptions: DisplayOptions(reducesMotion: true))
    let window = try #require(controller.window)
    defer { controller.close() }
    let top = window.frame.maxY

    for index in [1, 0, 1] {
      controller.tabs.selectedTabViewItemIndex = index

      let page = try #require(controller.tabs.tabViewItems[index].viewController)
      #expect(Self.fits(window, window.frame, page), "\(window.frame) \(page.preferredContentSize)")
      #expect(window.frame.maxY == top)
    }
  }

  @Test func windowSetsOutForTheSizeOfEachPageAndKeepsItsTopEdge() throws {
    // The animations of windows that the tests turn off are those that show and close them.
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let controller = SettingsWindowController(
      settings: .private(), updates: nil, displayOptions: DisplayOptions(reducesMotion: false))
    let window = try #require(controller.window)
    defer { controller.close() }
    let top = window.frame.maxY

    for index in [1, 0] {
      let start = window.frame
      controller.tabs.selectedTabViewItemIndex = index

      // The window moves rather than cuts: it still has its size, and the animator answers with
      // the frame it goes to. The frames on the way come from the screen, which shows none
      // while it is locked, so the test sets the end itself.
      let page = try #require(controller.tabs.tabViewItems[index].viewController)
      let end = window.animator().frame
      #expect(window.frame == start)
      #expect(Self.fits(window, end, page), "\(end) \(page.preferredContentSize)")
      #expect(end.maxY == top)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        window.animator().setFrame(end, display: false)
      }
    }
  }

  @Test func windowGoesOverToTheSizeOfEachPageWithoutPassingIt() async throws {
    WindowAnimations.turnOff()
    TransparentWindows.turnOn()
    let controller = SettingsWindowController(
      settings: .private(), updates: nil, displayOptions: DisplayOptions(reducesMotion: false))
    let window = try #require(controller.window)
    defer { controller.close() }
    let top = window.frame.maxY

    for index in [1, 0] {
      let page = try #require(controller.tabs.tabViewItems[index].viewController)
      let start = window.frame.height
      var heights: [CGFloat] = []
      let observer = NotificationCenter.default.addObserver(
        forName: NSWindow.didResizeNotification, object: window, queue: .main
      ) { _ in
        MainActor.assumeIsolated { heights.append(window.frame.height) }
      }
      defer { NotificationCenter.default.removeObserver(observer) }

      // Within a group of no duration, each animation of the window and of the pages takes its
      // end at once, whether the screen shows frames or not, so that every size the window is
      // sent to on its way, by the pages or by the tab view controller, is a size it takes.
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0
          controller.tabs.selectedTabViewItemIndex = index
        }, completionHandler: nil)
      // The window reaches the size of the page within a few seconds, however busy the machine.
      for _ in 0..<250 where !Self.fits(window, window.frame, page) {
        try await Task.sleep(for: .milliseconds(20))
      }

      #expect(Self.fits(window, window.frame, page), "\(window.frame) \(page.preferredContentSize)")
      #expect(window.frame.maxY == top)
      // On its way, the window is never sent beyond the size it starts from or the one it ends
      // at, and from one size it is sent to to the next, it moves along the animation it has
      // for its frame, which carries it beyond neither; so it never goes beyond them.
      let end = window.frame.height
      #expect(
        heights.allSatisfy { $0 >= min(start, end) && $0 <= max(start, end) },
        "\(start) \(heights) \(end)")
      #expect(Self.staysBetweenItsEnds(window.animation(forKey: "frame")))
    }
  }

  /// Whether `animation`, with which a window goes over to a frame, keeps it between the frame
  /// it starts from and the one it ends at: a basic animation between the two, not a spring,
  /// whose timing curve stays within them at every point sampled along its way.
  private static func staysBetweenItsEnds(_ animation: Any?) -> Bool {
    guard let animation = animation as? CABasicAnimation, !(animation is CASpringAnimation),
      animation.fromValue == nil, animation.toValue == nil, animation.byValue == nil
    else { return false }
    let timing = animation.timingFunction ?? CAMediaTimingFunction(name: .linear)
    let points = (0..<4).map { index in
      var values: [Float] = [0, 0]
      timing.getControlPoint(at: index, values: &values)
      return CGFloat(values[1])
    }
    return stride(from: 0, through: 1, by: 0.05).allSatisfy { (t: CGFloat) in
      let u = 1 - t
      // The share of the way at `t`, a point of the Bézier curve of the timing.
      let weights = [u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t]
      let progress = zip(weights, points).map(*).reduce(0, +)
      return progress >= 0 && progress <= 1
    }
  }

  /// Whether the content of `window` at `frame` has the size that `page` prefers, to the point
  /// that the window rounds it to.
  private static func fits(_ window: NSWindow, _ frame: CGRect, _ page: NSViewController) -> Bool {
    let content = window.contentRect(forFrameRect: frame).size
    let preferred = page.preferredContentSize
    return abs(content.width - preferred.width) <= 0.5
      && abs(content.height - preferred.height) <= 0.5
  }
}
