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

  /// Notes that the visible text moved, and discards, once scrolling has come to rest and the
  /// run loop is idle, the paragraph elements that TextKit holds for the rows more than a page
  /// below the visible text, a part at a time.
  ///
  /// TextKit keeps an element for every paragraph it has laid out and moves each one that
  /// follows an edit, so that after scrolling through a long text, every edit would take time in
  /// proportion to the text below it. An edit in view moves only the elements down to a page
  /// below it then. The elements above the visible text stay: TextKit finds the place of the
  /// view from them.
  func visibleTextDidMove() {
    if let lastShownRow {
      farthestRowShown = max(min(farthestRowShown, grid.rowCount - 1), lastShownRow)
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

  /// Plans to discard the rows from a page below the visible text to two pages beyond the
  /// farthest row that has been in view, as TextKit lays out somewhat beyond the visible text.
  @objc func scrollingDidRest(_ timer: Timer) {
    scrollRestTimer = nil
    interaction?.scrollingDidRest()
    guard let firstRow = firstRowBelowViewToDiscard else {
      finishDiscarding()
      return
    }
    let page = Int((visibleRect.height / theme.rowHeight).rounded(.up))
    let farthest = min(farthestRowShown, grid.rowCount - 1)
    let farthestLine = displayRows.lines(ofRows: farthest..<farthest + 1).lowerBound
    let end =
      displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: farthestLine + 2 * page))
      + 1
    guard firstRow < end else {
      finishDiscarding()
      return
    }
    rowsToDiscard = firstRow..<end
    resumeDiscardingParagraphs()
  }

  /// Asks for the next pass of discarding, if there are rows left and scrolling is at rest, once
  /// the run loop is idle; the passes coalesce.
  func resumeDiscardingParagraphs() {
    guard rowsToDiscard != nil, !isScrolling else { return }
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
    // The rows in view and a page below keep their elements, wherever the view is now.
    guard let scheduled = rowsToDiscard, let firstRow = firstRowBelowViewToDiscard else {
      finishDiscarding()
      return false
    }
    let start = max(scheduled.lowerBound, firstRow)
    let end = min(scheduled.upperBound, grid.rowCount)
    guard start < end else {
      finishDiscarding()
      return false
    }
    guard !hasMarkedText() else { return false }
    let part = start..<min(end, start + Self.rowsDiscardedAtOnce)
    contentStorage.discardElements(in: grid.paragraphOffsets(ofRows: part))
    if part.upperBound < end {
      rowsToDiscard = part.upperBound..<end
    } else {
      finishDiscarding()
    }
    return true
  }

  /// Ends discarding: TextKit holds no elements below the view beyond a page now, so the
  /// farthest row shown is the last one in view.
  private func finishDiscarding() {
    rowsToDiscard = nil
    farthestRowShown = lastShownRow ?? 0
  }

  /// The last row in view, or `nil` if the view has not been laid out in a window.
  private var lastShownRow: Int? {
    let visible = visibleRect
    guard window != nil, visible.height > 0 else { return nil }
    let line = Int((visible.maxY / theme.rowHeight).rounded(.up))
    return displayRows.row(atDisplayRow: displayRows.clampedDisplayRow(atLine: line))
  }

  /// The first row more than a page below the visible text, or `nil` if there is none or the
  /// view has not been laid out in a window.
  private var firstRowBelowViewToDiscard: Int? {
    let visible = visibleRect
    guard window != nil, visible.height > 0 else { return nil }
    let page = Int((visible.height / theme.rowHeight).rounded(.up))
    let line = Int((visible.maxY / theme.rowHeight).rounded(.up)) + page
    return line < displayRows.lineCount
      ? displayRows.row(atDisplayRow: displayRows.displayRow(atLine: line)) : nil
  }
}
