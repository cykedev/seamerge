import AppKit

extension PaneView {
  /// Hides `runs` behind bars and keeps the row at the top of the view where it is.
  ///
  /// The pane moves on its own here, without the panes coupled with it following: each of them
  /// keeps its own rows in place as its runs change.
  func collapse(_ runs: [CollapsedRun]) {
    guard runs != displayRows.runs else { return }
    let visible = clipView.bounds
    let topRow = displayRows.rowPosition(ofDisplay: Double(visible.minY / rowHeight))
    let barHadFocus = runBars.values.contains { window?.firstResponder === $0 }
    let change = {
      self.removeRunBars()
      self.textView.setCollapsedRuns(runs)
      self.showDisplayRows()
      self.needsLayout = true
      self.layoutSubtreeIfNeeded()
      let y = CGFloat(self.displayRows.displayPosition(ofRow: topRow)) * self.rowHeight
      self.scroll(
        to: CGPoint(x: visible.minX, y: min(max(y.rounded(), 0), self.verticalScrollRange)))
      self.placeRunBars()
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

  /// Shows a bar for each collapsed run in view, across the gutter and the text, and removes the
  /// bars of runs out of view.
  func placeRunBars() {
    let visible = clipView.bounds
    runBarLayer.frame = CGRect(
      x: 0, y: 0, width: gutterView.frame.width + clipView.frame.width,
      height: clipView.frame.height)
    let first = Int((visible.minY / rowHeight).rounded(.down))
    let end = Int((visible.maxY / rowHeight).rounded(.up))
    let indices = displayRows.runIndices(withBarsIn: first..<end)
    for (index, bar) in runBars where !indices.contains(index) {
      bar.removeFromSuperview()
      runBars[index] = nil
    }
    for index in indices {
      let bar = runBars[index] ?? makeRunBar(index)
      bar.contentInset = gutterView.frame.width + Theme.textInset
      bar.frame = CGRect(
        x: 0, y: CGFloat(displayRows.barRow(ofRun: index)) * rowHeight - visible.minY,
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
    let bar = CollapsedRunBar(
      runIndex: index, rowCount: displayRows.runs[index].rows.count, theme: theme)
    bar.target = self
    bar.action = #selector(runBarWasPressed(_:))
    bar.selectionFill = { [weak textView] in textView?.selectionFill }
    bar.paneName = { [weak self] in self?.accessibilityLabel() }
    runBarLayer.addSubview(bar)
    runBars[index] = bar
    markSelectedRunBars()
    return bar
  }

  @objc private func runBarWasPressed(_ sender: CollapsedRunBar) {
    askToExpandRun(at: sender.runIndex)
  }
}
