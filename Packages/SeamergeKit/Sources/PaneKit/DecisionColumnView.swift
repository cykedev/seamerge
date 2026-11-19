package import AppKit

/// The narrow column at the right edge of the result pane that shows how each block came by its
/// text and offers the toggles that decide it.
///
/// At the first row of each block stands its bar of toggles, `A ○ B`, always: a segment for each
/// input, quiet while the input is not taken, tinted while the merge took it, filled while the
/// user chose it, and the whole bar red while the block is an open conflict (``DecisionBar``).
/// Beside it is a place for the arrow that resets a block that differs from how it was loaded.
/// Every part stands in a slot of its own, the same in every row (``DecisionColumnLayout``), and
/// nothing changes under the pointer, so that a click always hits what it aims at. The column
/// shows what it is given and changes nothing on its own: it tells its delegate what the user
/// pressed.
///
/// Install the column on a pane with ``PaneView/decisionColumn``; the pane places it beside its
/// text and keeps it in step with its rows and its scroll position. Its width follows from the
/// slots, so that it never changes.
package final class DecisionColumnView: NSView {
  /// The colors and fonts of the column.
  package var theme = Theme() {
    didSet {
      for row in rowsByBlock.values {
        row.theme = theme
      }
      // The width follows the size of the text, which the pane lays out beside the column.
      superview?.needsLayout = true
      releasePinnedRow()
      update()
      needsDisplay = true
    }
  }

  /// What the column shows for each block, by the index of the block in the pane's content.
  ///
  /// A block without an entry has no row.
  package var decisions: [Int: BlockDecision] = [:] {
    didSet {
      // Decisions that come from anything but the press of the pinned row, such as typing or a
      // command of the keyboard or the menu, end its hold.
      if !isPressing {
        releasePinnedRow()
      }
      update()
    }
  }

  /// Whether the toggles and the reset arrows take the keyboard focus, so that Tab reaches them,
  /// the side arrow keys move between them and Space presses them, as Keyboard Navigation in the
  /// settings of the system asks.
  package var navigatesWithKeyboard = false

  /// Learns what the user presses; the column does not retain it.
  package weak var delegate: (any DecisionColumnDelegate)?

  /// The pane that the column stands in.
  weak var host: (any DecisionColumnHost)?

  /// The rows of the blocks in view, by the index of their block.
  private var rowsByBlock: [Int: DecisionRow] = [:]

  /// Where the rows stand, until the column updates.
  private var cachedRowPlaces: RowPlaces?

  /// The row whose controls the user pressed last, which keeps its place while its block
  /// changes under the click, so that a click never moves what it hit.
  ///
  /// The hold ends as soon as the user no longer aims at the row: when the pointer leaves it, or
  /// when anything else changes the layout, such as typing, a command, scrolling or the size of
  /// the text; the row then stands at its place beside its block again, at once.
  private var pinnedRow: PinnedRow?

  /// The area of the pinned row, which tells when the pointer leaves it.
  private var pinnedArea: NSTrackingArea?

  /// Whether the column is telling its delegate of a press, whose answer keeps the hold.
  private var isPressing = false

  /// Creates an empty column.
  package init() {
    super.init(frame: .zero)
    clipsToBounds = true
  }

  /// Decision columns are never archived.
  package required init?(coder: NSCoder) {
    nil
  }

  package override var isFlipped: Bool { true }

  /// Where the parts of its rows stand, for the rows of the text of the theme.
  var layout: DecisionColumnLayout {
    DecisionColumnLayout(theme: theme)
  }

  /// The width of the column: room for the slots of a row, rounded to the layout grid, which
  /// changes only with the size of the text.
  var width: CGFloat {
    layout.columnWidth
  }

  /// Places the rows of the blocks in view where their blocks now are: after the pane scrolled
  /// or changed its rows.
  func update() {
    cachedRowPlaces = nil
    showRows()
  }

  /// Where the rows stand: at their blocks, moved apart where two would stand on the same line,
  /// the row that was pressed last kept in place, and within the rows of the text.
  ///
  /// The rows of every block take part, so that a chain of close rows comes out the same
  /// wherever the pane is scrolled.
  private var rowPlaces: RowPlaces {
    if let cachedRowPlaces { return cachedRowPlaces }
    guard let host else { return RowPlaces(anchors: [], spacing: 0, within: 0...0) }
    if let pinnedRow, !pinnedRow.holds(in: host) {
      releasePinnedRow()
    }
    let anchors: [RowPlaces.Anchor] = decisions.keys.sorted().compactMap { block in
      guard let center = host.rowCenter(ofBlock: block) else { return nil }
      if let pinnedRow, pinnedRow.block == block {
        return RowPlaces.Anchor(
          block: block, center: pinnedRow.center, liesBetweenRows: false, isPinned: true)
      }
      return RowPlaces.Anchor(
        block: block, center: center, liesBetweenRows: host.liesBetweenRows(block))
    }
    let places = RowPlaces(
      anchors: anchors, spacing: layout.rowSpacing, within: host.rowsExtent)
    cachedRowPlaces = places
    return places
  }

  /// The block whose row lies at `y`, or else whose rows in the text do, if it has a decision.
  private func block(atY y: CGFloat) -> Int? {
    if let block = rowPlaces.block(atY: y, spacing: layout.rowSpacing) {
      return block
    }
    return host?.block(atY: y).flatMap { decisions[$0] == nil ? nil : $0 }
  }

  /// Gives a row to each block whose place is in view and takes it from the blocks out of view,
  /// except from a row that holds the keyboard focus.
  private func showRows() {
    guard let host else { return }
    let scale = window?.backingScaleFactor ?? 1
    let margin = max(layout.height, layout.rowSpacing)
    let inView = (bounds.minY - margin)...(bounds.maxY + margin)
    var shown: Set<Int> = []
    for (block, center) in rowPlaces.centers where inView ~= center {
      guard let decision = decisions[block] else { continue }
      let row = rowsByBlock[block] ?? makeRow(for: block)
      row.show(decision, place: host.placeDescription(ofBlock: block))
      row.frame = layout.rowFrame(centeredOn: center, scale: scale)
      shown.insert(block)
    }
    for (block, row) in rowsByBlock where !shown.contains(block) {
      let holdsFocus = row.controls.contains { window?.firstResponder === $0 }
      guard !holdsFocus || decisions[block] == nil || rowPlaces.centers[block] == nil else {
        continue
      }
      row.removeFromSuperview()
      rowsByBlock[block] = nil
      if holdsFocus {
        window?.makeFirstResponder(nil)
      }
    }
  }

  private func makeRow(for block: Int) -> DecisionRow {
    let row = DecisionRow(
      block: block, theme: theme, toggleAction: (self, #selector(toggleWasPressed(_:))),
      resetAction: (self, #selector(resetWasPressed(_:))))
    addSubview(row)
    rowsByBlock[block] = row
    return row
  }

  /// The rows that the column shows, from top to bottom.
  var rows: [DecisionRow] {
    rowsByBlock.values.sorted { $0.frame.minY < $1.frame.minY }
  }

  @objc private func toggleWasPressed(_ sender: DecisionToggleButton) {
    press(sender.block) {
      delegate?.decisionColumn(self, didSwitchToggle: sender.index, ofBlock: sender.block)
    }
  }

  @objc private func resetWasPressed(_ sender: ResetBlockButton) {
    press(sender.block) {
      delegate?.decisionColumn(self, didAskToResetBlock: sender.block)
    }
  }

  /// Keeps the row of `block` where it stands now, then tells the delegate of the press with
  /// `tell`; the block may change in the answer, the row stays.
  private func press(_ block: Int, tell: () -> Void) {
    if let host, let center = rowPlaces.centers[block], let blockTop = host.top(ofBlock: block),
      let row = rowsByBlock[block]
    {
      releasePinnedRow()
      pinnedRow = PinnedRow(
        block: block, center: center, blockTop: blockTop,
        contentGeneration: host.contentGeneration)
      // Inside from the start: a press of the keyboard ends the hold with the first move of the
      // pointer outside.
      let area = NSTrackingArea(
        rect: row.frame, options: [.mouseEnteredAndExited, .activeInKeyWindow, .assumeInside],
        owner: self)
      addTrackingArea(area)
      pinnedArea = area
    }
    isPressing = true
    defer { isPressing = false }
    tell()
  }

  /// Ends the hold of the pinned row; the next update puts the row beside its block.
  private func releasePinnedRow() {
    pinnedRow = nil
    if let pinnedArea {
      removeTrackingArea(pinnedArea)
      self.pinnedArea = nil
    }
  }

  /// Ends the hold of the pinned row once the pointer leaves it.
  package override func mouseExited(with event: NSEvent) {
    guard pinnedRow != nil else { return }
    releasePinnedRow()
    update()
  }

  /// Gives the keyboard focus to the first toggle of `block`, under Keyboard Navigation.
  ///
  /// - Returns: Whether a toggle took the focus; not if the block shows no row.
  package func focusToggles(ofBlock block: Int) -> Bool {
    guard navigatesWithKeyboard, let window,
      let control = rowsByBlock[block]?.controls.first(where: \.acceptsFirstResponder)
    else { return false }
    return window.makeFirstResponder(control)
  }

  /// Gives the pane that the column stands in the focus, as a click anywhere in it does.
  func focusPane() {
    host?.takeFocus()
  }

  /// The column takes the focus of a result in block mode, after a click beside its text, so
  /// that single keys decide blocks rather than type; Tab passes it by for its controls.
  package override var acceptsFirstResponder: Bool { true }

  package override var canBecomeKeyView: Bool { false }

  package override func becomeFirstResponder() -> Bool {
    defer { host?.focusDidChange() }
    return super.becomeFirstResponder()
  }

  package override func resignFirstResponder() -> Bool {
    defer { host?.focusDidChange() }
    return super.resignFirstResponder()
  }

  /// Scrolls the text for the page keys while the column has the focus; other keys that reach
  /// the column do nothing, as in block mode.
  package override func keyDown(with event: NSEvent) {
    interpretKeyEvents([event])
  }

  package override func doCommand(by selector: Selector) {
    if Self.scrollingCommands.contains(selector) {
      host?.scrollText(selector)
    }
  }

  /// The commands of keys that scroll the text without moving its insertion point.
  private static let scrollingCommands: Set<Selector> = [
    #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.scrollPageDown(_:)),
    #selector(NSResponder.scrollToBeginningOfDocument(_:)),
    #selector(NSResponder.scrollToEndOfDocument(_:)),
  ]

  package override func draw(_ dirtyRect: NSRect) {
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
  }

  /// Gives the pane the focus and tells the delegate which block the click is beside; a click on
  /// a control reaches the control instead.
  package override func mouseDown(with event: NSEvent) {
    focusPane()
    guard let block = block(atY: convert(event.locationInWindow, from: nil).y) else { return }
    delegate?.decisionColumn(self, didClickBlock: block)
  }

  /// The control under `point`: where the rows of blocks on lines one after the other reach into
  /// each other, the row whose middle lies nearest to the point.
  package override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard !isHidden, bounds.contains(local) else { return nil }
    let nearest = rows.filter { $0.frame.contains(local) }
      .min { abs($0.frame.midY - local.y) < abs($1.frame.midY - local.y) }
    return nearest?.hitTest(local) ?? self
  }

  /// Passes scrolling on to the pane, which scrolls its text.
  package override func scrollWheel(with event: NSEvent) {
    nextResponder?.scrollWheel(with: event)
  }

  package override func isAccessibilityElement() -> Bool {
    true
  }

  package override func accessibilityRole() -> NSAccessibility.Role? {
    .group
  }

  package override func accessibilityLabel() -> String? {
    String(
      localized: "Decisions", bundle: .module,
      comment: "VoiceOver: the column beside the result that shows how each block was decided.")
  }

  /// The rows of the blocks in view, from top to bottom.
  package override func accessibilityChildren() -> [Any]? {
    rows.filter { bounds.intersects($0.frame) }
  }
}

/// The row whose controls the user pressed last, by its block, and the place it holds.
private struct PinnedRow {
  /// The index of the block in the content that the pane showed when the row was pressed.
  var block: Int
  /// Where the middle of the row stood in the column.
  var center: CGFloat
  /// Where the top of the block stood in the column.
  var blockTop: CGFloat
  /// The content that the index of the block refers to, which no later content shares.
  var contentGeneration: Int

  /// Whether the row may still hold its place in `host`: its block is still the same block, of
  /// the same content, and its top has not moved by a point or more, as it would by scrolling,
  /// typing above it or another size of the text.
  ///
  /// Less than a point it may move when the clip view puts the text on whole pixels again as the
  /// height of the text changes; the row stays where it was then, to the pixel.
  @MainActor
  func holds(in host: any DecisionColumnHost) -> Bool {
    guard host.contentGeneration == contentGeneration, let top = host.top(ofBlock: block) else {
      return false
    }
    return abs(top - blockTop) < 1
  }
}

/// What the decision column needs to know of the pane it stands in.
@MainActor
protocol DecisionColumnHost: AnyObject {
  /// The vertical middle of the place that `block` asks for its row in the column: its first
  /// row, or for a block without rows the boundary where it lies; `nil` while that is behind the
  /// bar of a collapsed run.
  ///
  /// The column moves rows apart that would come too close; see ``RowPlaces``.
  func rowCenter(ofBlock block: Int) -> CGFloat?

  /// The top of the first row of `block`, or the boundary it lies on, in the column; `nil`
  /// while that is behind the bar of a collapsed run.
  func top(ofBlock block: Int) -> CGFloat?

  /// A number that changes whenever the pane gets other content, so that an index of a block
  /// never means a block of other content.
  var contentGeneration: Int { get }

  /// Whether `block` has no rows and lies on the boundary between two.
  func liesBetweenRows(_ block: Int) -> Bool

  /// Where the rows of the text lie in the column, from the top of the first to the bottom of
  /// the last, as the pane is scrolled.
  var rowsExtent: ClosedRange<CGFloat> { get }

  /// The block whose rows lie at `y` of the column, if any.
  func block(atY y: CGFloat) -> Int?

  /// Where `block` is, in words, such as "Line 12".
  func placeDescription(ofBlock block: Int) -> String

  /// Gives the pane the keyboard focus, as a click beside its text does.
  func takeFocus()

  /// Tells the pane that the column took the focus or gave it up.
  func focusDidChange()

  /// Scrolls the text of the pane as `command` asks, such as `scrollPageDown(_:)`.
  func scrollText(_ command: Selector)
}
