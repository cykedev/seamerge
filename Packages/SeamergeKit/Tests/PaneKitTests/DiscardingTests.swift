import AppKit
import Testing

@testable import PaneKit

/// Checks that a pane lets go of the layout that TextKit keeps for the paragraphs far below the
/// visible text, once the user has scrolled there and back, and that nothing else notices.
@MainActor
@Suite struct DiscardingTests {
  /// A text of 600 short lines.
  private static let text = (0..<600).map { "line \($0)" }.joined(separator: "\n")

  /// Scrolls `pane` to its end and back to `origin`, a page at a time, laying out the text on
  /// the way as the window does.
  private func scrollThrough(_ pane: PaneView, in window: NSWindow, backTo origin: CGPoint) {
    let page = pane.documentView.visibleRect.height
    var y: CGFloat = 0
    while y < pane.documentView.frame.height {
      pane.scroll(to: CGPoint(x: 0, y: y))
      window.contentView?.layoutSubtreeIfNeeded()
      y += page
    }
    pane.scroll(to: origin)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  /// Lets the wait for scrolling to rest end at once, as the timer does after the rest interval.
  private func letScrollingRest(_ textView: PaneTextView) {
    textView.scrollRestTimer?.fire()
  }

  /// The element that the content storage holds for the paragraph of `row`.
  private func element(ofRow row: Int, in textView: PaneTextView) throws -> NSTextElement {
    let storage = textView.contentStorage
    let location = try #require(
      storage.location(
        storage.documentRange.location, offsetBy: textView.grid.offsets(ofRow: row).lowerBound))
    var element: NSTextElement?
    _ = storage.enumerateTextElements(from: location) { found in
      element = found
      return false
    }
    return try #require(element)
  }

  /// Carries out every pass of discarding that the pane has scheduled for the idle run loop.
  private func discardEverything(in textView: PaneTextView) {
    while textView.discardNextParagraphs() {}
  }

  /// Whether TextKit has laid out the paragraph of `row`.
  private func isLaidOut(row: Int, of textView: PaneTextView) throws -> Bool {
    let manager = try #require(textView.textLayoutManager)
    let location = try #require(
      manager.location(
        manager.documentRange.location, offsetBy: textView.grid.offsets(ofRow: row).lowerBound))
    return manager.textLayoutFragment(for: location)?.state == .layoutAvailable
  }

  @Test func scrollingThroughAndBackDiscardsTheLayoutFarBelowTheView() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.textView
    scrollThrough(pane, in: window, backTo: .zero)
    letScrollingRest(textView)
    #expect(try isLaidOut(row: 500, of: textView))

    #expect(textView.rowsToDiscard != nil)
    discardEverything(in: textView)

    #expect(textView.rowsToDiscard == nil)
    #expect(try !isLaidOut(row: 500, of: textView))
    #expect(try isLaidOut(row: 0, of: textView))
  }

  /// Discarding makes the content storage make new elements for the paragraphs below the view.
  ///
  /// TextKit drops the elements of paragraphs only where the text storage reports an edit; the
  /// pane relies on it doing so for an edit of attributes that changes none, which no
  /// documentation promises. This test guards that behavior for new versions of macOS: should it
  /// change, discarding keeps the elements and editing after scrolling is slow again.
  @Test func discardingMakesTheStorageLetGoOfTheElementsBelowTheView() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.textView
    scrollThrough(pane, in: window, backTo: .zero)
    letScrollingRest(textView)
    let below = try element(ofRow: 500, in: textView)
    let inView = try element(ofRow: 2, in: textView)
    #expect(try element(ofRow: 500, in: textView) === below)

    discardEverything(in: textView)

    #expect(try element(ofRow: 500, in: textView) !== below)
    #expect(try element(ofRow: 2, in: textView) === inView)
  }

  @Test func nothingIsDiscardedWhileTheViewMovesButOnceScrollingRests() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.textView
    scrollThrough(pane, in: window, backTo: .zero)
    let rowHeight = pane.theme.rowHeight
    for step in 1...5 {
      pane.scroll(to: CGPoint(x: 0, y: CGFloat(step) * rowHeight))
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(textView.isScrolling)
      #expect(!textView.discardNextParagraphs())
    }
    let scrollView = try #require(textView.enclosingScrollView)
    NotificationCenter.default.post(
      name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
    pane.scroll(to: CGPoint(x: 0, y: 8 * rowHeight))
    #expect(textView.scrollRestTimer == nil)
    #expect(!textView.discardNextParagraphs())
    NotificationCenter.default.post(
      name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
    #expect(!textView.discardNextParagraphs())
    #expect(try isLaidOut(row: 500, of: textView))

    letScrollingRest(textView)

    #expect(!textView.isScrolling)
    discardEverything(in: textView)
    #expect(try !isLaidOut(row: 500, of: textView))
  }

  @Test func rowsOnceInViewAtTheEndAreDiscardedAfterScrollingBackToTheTop() throws {
    let (pane, window, _) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.textView
    for y in [0, 300 * pane.theme.rowHeight, textView.frame.height - textView.visibleRect.height] {
      pane.scroll(to: CGPoint(x: 0, y: y))
      window.contentView?.layoutSubtreeIfNeeded()
      letScrollingRest(textView)
      discardEverything(in: textView)
    }
    #expect(try isLaidOut(row: 595, of: textView))

    pane.scroll(to: .zero)
    window.contentView?.layoutSubtreeIfNeeded()
    letScrollingRest(textView)
    discardEverything(in: textView)

    #expect(try !isLaidOut(row: 595, of: textView))
    #expect(try !isLaidOut(row: 300, of: textView))
  }

  @Test func discardingChangesNothingThatTheOwnerOrTheUserCouldNotice() throws {
    let previewStart = Self.text.utf16.count - 20
    let (pane, window, recorder) = EditingTests.editablePane(
      text: Self.text, blocks: [PaneBlock(rows: 590..<600, style: .tinted(.conflict))],
      previews: [PanePreview(range: previewStart..<Self.text.utf16.count, role: .b)])
    defer { window.close() }
    let textView = pane.textView
    pane.setBlocks(
      pane.content.blocks, previews: pane.content.previews, rowTints: [400: .handwritten])
    pane.setContent(pane.content, collapsedRuns: [CollapsedRun(rows: 100..<200)])
    let undoManager = UndoManager()
    let undoOwner = UndoOwner(undoManager: undoManager)
    window.delegate = undoOwner
    var textChanges = 0
    let observer = NotificationCenter.default.addObserver(
      forName: NSText.didChangeNotification, object: textView, queue: nil
    ) { _ in MainActor.assumeIsolated { textChanges += 1 } }
    defer { NotificationCenter.default.removeObserver(observer) }
    let origin = CGPoint(x: 0, y: 5 * pane.theme.rowHeight)
    scrollThrough(pane, in: window, backTo: origin)
    letScrollingRest(textView)
    textView.setSelectedRange(NSRange(location: 30, length: 4))
    let colored = try DrawnColors.coloredRanges(in: textView)
    let accessibilityValue = textView.accessibilityValue()

    discardEverything(in: textView)

    #expect(try !isLaidOut(row: 500, of: textView))
    #expect(recorder.asked.isEmpty && recorder.carriedOut.isEmpty && recorder.unannounced.isEmpty)
    #expect(textChanges == 0)
    #expect(!undoManager.canUndo)
    #expect(textView.string == Self.text)
    #expect(textView.accessibilityValue() == accessibilityValue)
    #expect(
      textView.selectedRanges.map(\.rangeValue) == [NSRange(location: 30, length: 4)])
    #expect(textView.visibleRect.origin == origin)
    #expect(pane.content.blocks == [PaneBlock(rows: 590..<600, style: .tinted(.conflict))])
    #expect(
      pane.content.previews == [PanePreview(range: previewStart..<Self.text.utf16.count, role: .b)])
    #expect(pane.content.rowTints == [400: .handwritten])
    #expect(pane.collapsedRuns == [CollapsedRun(rows: 100..<200)])
    #expect(try DrawnColors.coloredRanges(in: textView) == colored)
    #expect(!colored.isEmpty)
  }

  @Test func discardingWaitsWhileTheInputMethodMarksText() throws {
    let (pane, window, recorder) = EditingTests.editablePane(text: Self.text)
    defer { window.close() }
    let textView = pane.textView
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    scrollThrough(pane, in: window, backTo: .zero)
    letScrollingRest(textView)
    textView.setMarkedText(
      "´", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.markedRange() == NSRange(location: 4, length: 1))

    textView.discardNextParagraphsWhenIdle(
      Notification(name: PaneTextView.idleToDiscardNotification, object: textView))
    #expect(!textView.isDiscardPassPending)
    #expect(try isLaidOut(row: 500, of: textView))
    #expect(textView.markedRange() == NSRange(location: 4, length: 1))

    textView.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(recorder.carriedOut.count == 2)
    #expect(textView.isDiscardPassPending)
    discardEverything(in: textView)
    #expect(try !isLaidOut(row: 500, of: textView))
  }
}

/// Gives a window an undo manager of the test's own, to see whether anything registers an undo.
@MainActor
private final class UndoOwner: NSObject, NSWindowDelegate {
  let undoManager: UndoManager

  init(undoManager: UndoManager) {
    self.undoManager = undoManager
  }

  func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
    undoManager
  }
}
