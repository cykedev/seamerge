import AppKit

extension PaneView {
  /// Hides `runs` behind bars and keeps the row at the top of the view where it is.
  ///
  /// The pane moves on its own here, without the panes coupled with it following: each of them
  /// keeps its own rows in place as its runs change.
  func collapse(_ runs: [CollapsedRun]) {
    guard runs != displayRows.runs else { return }
    let visible = clipView.bounds
    let topRow = displayRows.rowPosition(ofLine: Double(visible.minY / rowHeight))
    let barHadFocus = runBars.values.contains { window?.firstResponder === $0 }
    let change = {
      self.removeRunBars()
      self.textView.setCollapsedRuns(runs)
      self.showDisplayRows()
      // The text lays itself out in the next layout, at the place the pane shows then: revealing
      // a match or a block behind the run moves the pane on at once, and laying out the lines at
      // the place it leaves, which may be very long, would be in vain. The place to keep needs
      // only the new height.
      self.needsLayout = true
      self.fitTextViewHeight()
      let y = CGFloat(self.displayRows.linePosition(ofRow: topRow)) * self.rowHeight
      // Where the runs above stay as they were, the text stays to the fraction of a point, so
      // that nothing in view moves, not even by rounding.
      let target = abs(y - visible.minY) < 0.01 ? visible.minY : y.rounded()
      self.scroll(
        to: CGPoint(x: visible.minX, y: min(max(target, 0), self.verticalScrollRange)))
      // The bars, the gutter and the decision column follow the rows now, as the layout of the
      // pane would have them.
      self.textDidScroll()
    }
    if let scrollSync {
      scrollSync.withoutFollowing(change)
    } else {
      change()
    }
    // The bar that the user pressed is gone with its run; the focus stays in the pane.
    if barHadFocus {
      window?.makeFirstResponder(textView)
    }
  }

  /// Gives the keyboard focus to the bar of `run`, one of the collapsed runs, if it is in view:
  /// after the user collapsed the run again, so that the focus stays where it was.
  ///
  /// - Returns: Whether the bar took the focus.
  @discardableResult
  package func focusBar(of run: CollapsedRun) -> Bool {
    guard let index = displayRows.runs.firstIndex(of: run) else { return false }
    layoutSubtreeIfNeeded()
    placeRunBars()
    guard let bar = runBars[index], let window else { return false }
    return window.makeFirstResponder(bar)
  }

  /// Shows a bar for each collapsed run in view, across the gutter and the text, and removes the
  /// bars of runs out of view.
  func placeRunBars() {
    let visible = clipView.bounds
    runBarLayer.frame = CGRect(
      x: 0, y: 0, width: gutterView.frame.width + clipView.frame.width,
      height: clipView.frame.height)
    let first = displayRows.displayRow(atLine: Int((visible.minY / rowHeight).rounded(.down)))
    let endLine = Int((visible.maxY / rowHeight).rounded(.up))
    let end = endLine > 0 ? displayRows.displayRow(atLine: endLine - 1) + 1 : 0
    let indices = displayRows.runIndices(withBarsIn: first..<max(first, end))
    for (index, bar) in runBars where !indices.contains(index) {
      bar.removeFromSuperview()
      runBars[index] = nil
    }
    for index in indices {
      let bar = runBars[index] ?? makeRunBar(index)
      bar.contentInset = gutterView.frame.width + Theme.textInset
      bar.frame = CGRect(
        x: 0,
        y: CGFloat(displayRows.firstLine(ofDisplayRow: displayRows.barRow(ofRun: index)))
          * rowHeight - visible.minY,
        width: runBarLayer.frame.width, height: rowHeight)
    }
  }

  /// Removes every bar, for runs that changed; the next layout places the bars of the new ones.
  func removeRunBars() {
    for bar in runBars.values {
      bar.removeFromSuperview()
    }
    runBars.removeAll()
  }

  /// Shows on each bar in view whether the selection takes in the rows that its run hides.
  ///
  /// The bars draw the fill of the selection when they draw, after a change of focus has
  /// settled.
  func markSelectedRunBars() {
    let selections = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }.map {
      $0.location..<$0.location + $0.length
    }
    for bar in runBars.values {
      let rows = displayRows.runs[bar.runIndex].rows
      let start = textView.grid.offsets(ofRow: rows.lowerBound).lowerBound
      let end = textView.grid.offsets(ofRow: rows.upperBound - 1).upperBound
      let isWithinSelection = selections.contains { $0.overlaps(start..<end) }
      if isWithinSelection || bar.isWithinSelection {
        bar.needsDisplay = true
      }
      bar.isWithinSelection = isWithinSelection
    }
  }

  private func makeRunBar(_ index: Int) -> CollapsedRunBar {
    let run = displayRows.runs[index]
    let bar = CollapsedRunBar(
      runIndex: index, lineCount: run.missingLineCount ?? run.rows.count, expands: run.expands,
      theme: theme)
    if run.expands {
      bar.target = self
      bar.action = #selector(runBarWasPressed(_:))
    }
    bar.selectionFill = { [weak textView] in textView?.selectionFill }
    bar.paneName = { [weak self] in self?.accessibilityLabel() }
    bar.focusPane = { [weak self] in self?.takeFocus() }
    runBarLayer.addSubview(bar)
    runBars[index] = bar
    markSelectedRunBars()
    return bar
  }

  @objc private func runBarWasPressed(_ sender: CollapsedRunBar) {
    askToExpandRun(at: sender.runIndex)
  }
}
