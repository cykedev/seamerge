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

  /// The most pages of rows beyond those kept that the view may leave behind with their layout
  /// as it scrolls, before the pane discards them without waiting for scrolling to rest; the
  /// more there may be, the fewer passes scrolling takes.
  static let pagesLeftBehind = 6

  /// How many rows left behind the pane may discard while the view scrolls, for each row it
  /// scrolled since it last did: more than one, so that it catches up with what jumps left, and
  /// few enough that a step of scrolling never waits long for it.
  static let rowsDiscardedPerRowScrolled = 4

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
  ///
  /// While the view scrolls, by a page or less at a time, the pane already discards the rows
  /// that lie beyond those pages once they make up more than ``pagesLeftBehind`` pages, so that
  /// scrolling a long way, or stepping from change to change, never holds the layout of more
  /// than a few pages beyond the view. A jump leaves the place it left laid out, to jump back
  /// to, until the view rests or scrolls on.
  func visibleTextDidMove() {
    updateDrawnSpan()
    if let rows = rows(aroundViewByPages: 2) {
      rowsNearView.insert(integersIn: rows)
    }
    let top = visibleRect.minY
    if let last = visibleTopAtLastMove, abs(top - last) <= visibleRect.height {
      rowsScrolledSinceDiscarding += Int((abs(top - last) / theme.rowHeight).rounded(.up))
      discardRowsLeftBehind()
    }
    visibleTopAtLastMove = top
    waitForScrollingToRest()
  }

  /// Discards the paragraph elements of the rows near the view before that now lie more than
  /// ``pagesKept`` pages from it, once they make up more than ``pagesLeftBehind`` pages and the
  /// view has scrolled a page since the pane last did: the rows farthest from the view first,
  /// at most ``rowsDiscardedPerRowScrolled`` for each row scrolled, and at most
  /// ``rowsDiscardedAtOnce``.
  ///
  /// It takes time in proportion to the rows scrolled, a part of the time that laying them out
  /// took, also where the rows left behind are many, as after collapsed rows that TextKit laid
  /// out with no height. While the input method marks text, or the text changes, the rows wait
  /// for the next move or for scrolling to rest.
  private func discardRowsLeftBehind() {
    let page = rowsPerPage
    guard rowsScrolledSinceDiscarding >= page,
      let kept = rows(aroundViewByPages: Self.pagesKept), !hasMarkedText(), !isShowingContent,
      textStorage?.editedMask.isEmpty != false
    else { return }
    var leftBehind = rowsNearView.intersection(IndexSet(integersIn: 0..<grid.rowCount))
    leftBehind.remove(integersIn: kept)
    guard leftBehind.count > Self.pagesLeftBehind * page else { return }
    var count = min(
      Self.rowsDiscardedAtOnce, Self.rowsDiscardedPerRowScrolled * rowsScrolledSinceDiscarding)
    rowsScrolledSinceDiscarding = 0
    let middle = (kept.lowerBound + kept.upperBound) / 2
    var discarded = IndexSet()
    while count > 0, let first = leftBehind.first, let last = leftBehind.last {
      let row = middle - first >= last - middle ? first : last
      leftBehind.remove(row)
      discarded.insert(row)
      count -= 1
    }
    contentStorage.discardElements(
      in: discarded.rangeView.map { grid.paragraphOffsets(ofRows: $0) })
    rowsNearView.subtract(discarded)
    rowsToDiscard.subtract(discarded)
  }

  /// The number of rows of a page, the visible height.
  private var rowsPerPage: Int {
    max(1, Int((visibleRect.height / theme.rowHeight).rounded(.up)))
  }

  /// Notes that the user started scrolling by hand, with the scroller or a gesture: the passes
  /// that wait for scrolling to rest wait until it ends.
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

  /// Stops waiting for scrolling to rest and for the run loop to be idle, as the view leaves its
  /// window.
  ///
  /// The timer and the queued notification would keep the view, and with it its text and every
  /// fragment laid out, until they fire. The rows near the view stay for when it comes back into
  /// a window (``resumeDiscarding()``).
  func pauseDiscarding() {
    scrollRestTimer?.invalidate()
    scrollRestTimer = nil
    isLiveScrolling = false
    guard isDiscardPassPending else { return }
    NotificationQueue.default.dequeueNotifications(
      matching: Notification(name: Self.idleToDiscardNotification, object: self),
      coalesceMask: Int(NotificationQueue.NotificationCoalescing([.onName, .onSender]).rawValue))
    isDiscardPassPending = false
  }

  /// Waits for scrolling to rest anew as the view comes back into a window, if TextKit may hold
  /// elements away from the view, so that the passes of discarding plan them once the view is
  /// laid out in its window.
  func resumeDiscarding() {
    guard !rowsNearView.isEmpty || !rowsToDiscard.isEmpty else { return }
    waitForScrollingToRest()
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
    let margin = pages * rowsPerPage
    let first = row(atLine: Int((visible.minY / theme.rowHeight).rounded(.down)) - margin)
    let last = row(atLine: Int((visible.maxY / theme.rowHeight).rounded(.up)) + margin)
    return first..<last + 1
  }

  /// The row shown on screen line `line`, or on the first or last line if `line` lies beyond.
  private func row(atLine line: Int) -> Int {
    displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: max(0, line)))
  }
}
