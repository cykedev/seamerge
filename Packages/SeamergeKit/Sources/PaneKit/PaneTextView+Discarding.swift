import AppKit

extension PaneTextView {
  /// The most rows whose paragraph elements one pass discards, so that a pass takes a few
  /// milliseconds even where TextKit holds an element for each of them.
  static let rowsDiscardedAtOnce = 1_000

  /// How long the visible text has to stay where it is before scrolling counts as at rest,
  /// longer than the gaps between the events of a scroll wheel or the momentum of a trackpad.
  static let scrollingRestInterval: TimeInterval = 0.3

  /// Posted to the text view itself when the run loop is idle, to discard the next rows.
  static let idleToDiscardNotification = Notification.Name("PaneTextViewIdleToDiscard")

  /// The pages of rows above and below the visible text whose paragraph elements stay when the
  /// pane discards the others.
  static let pagesKept = 3

  /// Notes that the visible text moved, and discards, once scrolling has come to rest and the
  /// run loop is idle, the paragraph elements that TextKit holds for the rows more than
  /// ``pagesKept`` pages above or below the visible text, a part at a time.
  ///
  /// TextKit keeps an element for every paragraph it has laid out, with the layout of its
  /// lines, and moves each one that follows an edit. After scrolling through a long text, every
  /// edit would take time in proportion to the text below it, and the layout of every line
  /// shown would stay in memory: for lines thousands of characters long, hundreds of kilobytes
  /// each. TextKit finds the place of the view without the elements above it, since the pane
  /// lays out the first visible row before the rest (``layOutFirstVisibleRow()``).
  func visibleTextDidMove() {
    updateDrawnSpan()
    if let rows = rows(aroundViewByPages: 2) {
      rowsNearView.insert(integersIn: rows)
    }
    waitForScrollingToRest()
  }

  /// Notes that the user started scrolling by hand, with the scroller or a gesture: nothing is
  /// discarded until it ends.
  func liveScrollDidStart() {
    isLiveScrolling = true
    scrollRestTimer?.invalidate()
    scrollRestTimer = nil
  }

  /// Notes that the user stopped scrolling by hand.
  func liveScrollDidEnd() {
    isLiveScrolling = false
    waitForScrollingToRest()
  }

  /// Whether the user is scrolling, or the visible text moved less than the rest interval ago.
  var isScrolling: Bool {
    isLiveScrolling || scrollRestTimer != nil
  }

  /// Starts the wait for scrolling to rest anew, in the default mode of the run loop only.
  private func waitForScrollingToRest() {
    scrollRestTimer?.invalidate()
    scrollRestTimer = nil
    guard !isLiveScrolling else { return }
    let timer = Timer(
      timeInterval: Self.scrollingRestInterval, target: self,
      selector: #selector(scrollingDidRest(_:)), userInfo: nil, repeats: false)
    RunLoop.current.add(timer, forMode: .default)
    scrollRestTimer = timer
  }

  /// Plans to discard the rows that TextKit may hold and that lie more than ``pagesKept`` pages
  /// from the visible text.
  @objc func scrollingDidRest(_ timer: Timer) {
    scrollRestTimer = nil
    interaction?.scrollingDidRest()
    rowsToDiscard = rowsNearView
    resumeDiscardingParagraphs()
  }

  /// Asks for the next pass of discarding, if there are rows left and scrolling is at rest, once
  /// the run loop is idle; the passes coalesce.
  func resumeDiscardingParagraphs() {
    guard !rowsToDiscard.isEmpty, !isScrolling else { return }
    isDiscardPassPending = true
    NotificationQueue.default.enqueue(
      Notification(name: Self.idleToDiscardNotification, object: self), postingStyle: .whenIdle,
      coalesceMask: [.onName, .onSender], forModes: nil)
  }

  /// Carries out a pass of discarding and asks for the next one.
  @objc func discardNextParagraphsWhenIdle(_ notification: Notification) {
    isDiscardPassPending = false
    if discardNextParagraphs() {
      resumeDiscardingParagraphs()
    }
  }

  /// Discards the paragraph elements of the next rows still to be discarded, unless the user is
  /// scrolling, which plans the passes anew once it rests, or the input method marks text, which
  /// asks for the next pass once it ends: discarding changes no text, but it is no time to touch
  /// the text storage.
  ///
  /// Returns whether it discarded any.
  @discardableResult
  func discardNextParagraphs() -> Bool {
    guard !isScrolling else { return false }
    // The rows near the view keep their elements, wherever the view is now.
    guard let kept = rows(aroundViewByPages: Self.pagesKept) else {
      finishDiscarding()
      return false
    }
    rowsToDiscard.remove(integersIn: kept)
    rowsToDiscard = rowsToDiscard.intersection(IndexSet(integersIn: 0..<grid.rowCount))
    guard let next = rowsToDiscard.rangeView.first else {
      finishDiscarding()
      return false
    }
    guard !hasMarkedText() else { return false }
    let part = next.lowerBound..<min(next.upperBound, next.lowerBound + Self.rowsDiscardedAtOnce)
    contentStorage.discardElements(in: grid.paragraphOffsets(ofRows: part))
    rowsToDiscard.remove(integersIn: part)
    if rowsToDiscard.isEmpty {
      finishDiscarding()
    }
    return true
  }

  /// Ends discarding: TextKit holds no elements beyond the rows near the view.
  private func finishDiscarding() {
    rowsToDiscard = IndexSet()
    rowsNearView = rows(aroundViewByPages: 2).map { IndexSet(integersIn: $0) } ?? IndexSet()
  }

  /// The rows in view and `pages` pages above and below, or `nil` if the view has not been laid
  /// out in a window.
  private func rows(aroundViewByPages pages: Int) -> Range<Int>? {
    let visible = visibleRect
    guard window != nil, visible.height > 0, grid.rowCount > 0 else { return nil }
    let margin = pages * Int((visible.height / theme.rowHeight).rounded(.up))
    let first = row(atLine: Int((visible.minY / theme.rowHeight).rounded(.down)) - margin)
    let last = row(atLine: Int((visible.maxY / theme.rowHeight).rounded(.up)) + margin)
    return first..<last + 1
  }

  /// The row shown on screen line `line`, or on the first or last line if `line` lies beyond.
  private func row(atLine line: Int) -> Int {
    displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: max(0, line)))
  }
}
