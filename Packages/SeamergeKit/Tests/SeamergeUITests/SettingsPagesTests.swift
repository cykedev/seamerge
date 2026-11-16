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
      #expect(Self.fits(window, page), "\(window.frame) \(page.preferredContentSize)")
      #expect(window.frame.maxY == top)
    }
  }

  @Test func windowGoesOverToTheSizeOfEachPageWithoutPassingIt() async throws {
    // The animations of windows that the tests turn off are those that show and close them.
    WindowAnimations.turnOff()
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

      controller.tabs.selectedTabViewItemIndex = index
      // The window reaches the size of the page within a few seconds, however busy the machine.
      for _ in 0..<250 where !Self.fits(window, page) {
        try await Task.sleep(for: .milliseconds(20))
      }

      #expect(Self.fits(window, page), "\(window.frame) \(page.preferredContentSize)")
      #expect(window.frame.maxY == top)
      // On its way, the window never goes beyond the size it starts from or the one it ends at.
      let end = window.frame.height
      #expect(
        heights.allSatisfy { $0 >= min(start, end) && $0 <= max(start, end) },
        "\(start) \(heights) \(end)")
    }
  }

  /// Whether the content of `window` has the size that `page` prefers, to the point that the
  /// window rounds it to.
  private static func fits(_ window: NSWindow, _ page: NSViewController) -> Bool {
    let content = window.contentRect(forFrameRect: window.frame).size
    let preferred = page.preferredContentSize
    return abs(content.width - preferred.width) <= 0.5
      && abs(content.height - preferred.height) <= 0.5
  }
}
