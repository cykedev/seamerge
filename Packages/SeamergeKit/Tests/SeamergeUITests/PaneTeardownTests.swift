import AppKit
import Testing

@testable import PaneKit

/// A pane that goes lets go of its text and of the layout of it, which AppKit may keep alive
/// once the text view is gone.
///
/// It lives among the tests of windows, which run one at a time: AppKit lets the text view go
/// only once the main queue is idle, which it hardly ever is while other tests run beside.
@MainActor
@Suite struct PaneTeardownTests {
  @Test func paneThatGoesLeavesItsContentStorageWithoutTextOrLayout() async throws {
    let text = (0..<600).map { "line \($0)" }.joined(separator: "\n")
    weak var textView: PaneTextView?
    let storage = autoreleasepool { () -> PaneContentStorage in
      let pane = PaneView()
      pane.content = PaneContent(
        text: text, lineNumbers: (0..<600).map { Int32($0) }, blocks: [])
      textView = pane.textView
      #expect(pane.textView.contentStorage.textLayoutManagers.count == 1)
      #expect(pane.textView.contentStorage.textStorage?.length == text.utf16.count)
      return pane.textView.contentStorage
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while textView != nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(textView == nil)

    #expect(storage.textLayoutManagers.isEmpty)
    #expect(storage.textStorage?.length == 0)
  }
}
