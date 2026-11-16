import AppKit

/// Receives the clicks on the marks of an overview bar.
@MainActor
public protocol OverviewBarDelegate: AnyObject {
  /// Tells the delegate that the mark of `block` was clicked, or pressed with VoiceOver.
  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int)
}

/// The vertical scroller of a pane that also shows where the text changes: a mark for each
/// block, the visible part of the text as a frame across the bar, the current block with a small
/// triangle.
///
/// The bar is a scroller like any other, so dragging, scrolling and VoiceOver work as they do
/// elsewhere. It keeps its width whatever scroller style the system uses, since the marks are
/// meant to be seen at all times. A click on the track pages or jumps to the spot as the user set
/// it in the system; a click that jumps to a mark also reports its block.
///
/// Install the bar on a pane with `PaneView.overviewBar`; the pane places it, tells it its rows
/// and scrolls when it acts. Marks name rows of the grid; the bar draws them where the pane shows
/// them, with its collapsed runs.
public final class OverviewBar: NSScroller {
  /// The colors of the marks and areas.
  public var theme = Theme() {
    didSet { invalidateLayout() }
  }

  /// The marks, in row order.
  public var marks: [OverviewMark] = [] {
    didSet { invalidateLayout() }
  }

  /// The rows of the grid that hold a match of the search, each marked with a stroke across the
  /// bar, above the marks of the blocks; strokes that touch merge.
  ///
  /// Like marks, the rows name rows of the grid; a row behind a collapsed run is marked on its
  /// bar.
  public var matchRows = IndexSet() {
    didSet { invalidateLayout() }
  }

  /// The index of the current block, whose mark the triangle points at, or `nil` if there is
  /// none.
  ///
  /// Where several marks name the block, as the parts of a block in a single column do, the
  /// triangle points at the middle of all of them.
  public var currentBlock: Int? {
    didSet { needsDisplay = true }
  }

  /// Receives clicks on the marks.
  public weak var delegate: (any OverviewBarDelegate)?

  /// Whether the bar is moving its knob to a mark that VoiceOver pressed, so that its action asks
  /// to scroll there whatever part of the bar the mouse hit last.
  private(set) var isPlacingKnob = false

  /// The rows of the pane that the bar scrolls, as the pane shows them.
  var displayRows = DisplayRows(runs: [], rowCount: 1) {
    didSet { invalidateLayout() }
  }

  private var cachedLayout: OverviewLayout?
  private var cachedMarkElements: [MarkElement]?

  /// The block whose marks ``cachedCurrentBlockRect`` covers, if it holds any.
  private var cachedCurrentBlock: Int?

  /// What the marks of ``cachedCurrentBlock`` cover, `nil` if it has none, found once for each
  /// layout and current block rather than on every step of scrolling.
  private var cachedCurrentBlockRect: CGRect?

  /// Whether the pointer is over the bar or drags its frame, which then draws stronger.
  private(set) var isEmphasized = false {
    didSet {
      if isEmphasized != oldValue {
        invalidateVisibleRegion()
      }
    }
  }

  /// The area that tells when the pointer enters and leaves the bar.
  private var pointerArea: NSTrackingArea?

  private var isPointerInside = false {
    didSet { isEmphasized = isPointerInside || isTracking }
  }

  private var isTracking = false {
    didSet { isEmphasized = isPointerInside || isTracking }
  }

  /// Creates an overview bar without marks.
  public init() {
    super.init(frame: CGRect(x: 0, y: 0, width: Theme.overviewBarWidth, height: 100))
    setAccessibilityLabel(String(localized: "Overview", bundle: .module))
  }

  /// Overview bars are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  public override class func scrollerWidth(
    for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style
  ) -> CGFloat {
    Theme.overviewBarWidth
  }

  /// The bar always takes its room beside the text; overlay scrollers would hide it while the
  /// text rests.
  public override var scrollerStyle: NSScroller.Style {
    get { .legacy }
    set { super.scrollerStyle = .legacy }
  }

  public override var isOpaque: Bool { true }

  // The frame of the visible part is drawn with the bar, which the scroller would not draw
  // again when only its knob moves: the stripe of the frame is drawn again where it was and
  // where it is now, and nothing else.
  public override var doubleValue: Double {
    willSet { invalidateVisibleRegion() }
    didSet { invalidateVisibleRegion() }
  }

  public override var knobProportion: CGFloat {
    willSet { invalidateVisibleRegion() }
    didSet { invalidateVisibleRegion() }
  }

  /// Has the stripe of the bar that the frame of the visible part covers drawn again.
  private func invalidateVisibleRegion() {
    let knob = rect(for: .knob)
    guard !knob.isEmpty else { return }
    let margin = Theme.visibleRegionOutlineWidth
    setNeedsDisplay(
      CGRect(
        x: bounds.minX, y: knob.minY - margin, width: bounds.width,
        height: knob.height + 2 * margin))
  }

  public override func setFrameSize(_ newSize: NSSize) {
    let changed = newSize != frame.size
    super.setFrameSize(newSize)
    if changed {
      invalidateLayout()
    }
  }

  public override func draw(_ dirtyRect: NSRect) {
    Theme.backgroundColor.setFill()
    dirtyRect.fill()
    theme.overviewBackgroundTone.setFill()
    dirtyRect.fill(using: .sourceOver)
    NSColor.separatorColor.setFill()
    CGRect(x: 0, y: dirtyRect.minY, width: Self.hairline(in: self), height: dirtyRect.height)
      .fill(using: .sourceOver)
    let layout = layout
    // A scroll step draws only the stripe of the frame; the marks elsewhere stay as they are.
    for shape in layout.shapes where shape.rect.intersects(dirtyRect) {
      drawMark(shape)
    }
    for span in layout.matchSpans where span.overlaps(dirtyRect.minY..<dirtyRect.maxY) {
      drawMatchStroke(span)
    }
    drawVisibleRegion()
    drawCurrentBlockIndicator(layout)
  }

  /// Scrolls the way the user set clicks in scroll bars to work, and reports the block of a
  /// mark when a click on it jumps there.
  public override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let knob = rect(for: .knob)
    let block = point.y < knob.minY || point.y > knob.maxY ? layout.block(at: point.y) : nil
    // The scroller tracks the mouse until the button goes up: it pages or jumps to the spot as
    // the system setting says, and drags the knob.
    isTracking = true
    super.mouseDown(with: event)
    endTracking(releasedAt: Self.releaseLocation(in: window))
    if let block, hitPart != .decrementPage, hitPart != .incrementPage {
      delegate?.overviewBar(self, didSelectBlock: block)
    }
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    guard pointerArea == nil else { return }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    pointerArea = area
  }

  /// Ends the tracking of a click or a drag whose mouse button went up at `location`, in the
  /// coordinates of the window: the frame stays strong only if the pointer is still over the
  /// bar.
  ///
  /// The bar hears of no exit while the scroller tracks the mouse, so the place of the release
  /// tells where the pointer is.
  func endTracking(releasedAt location: CGPoint?) {
    isTracking = false
    isPointerInside = location.map { bounds.contains(convert($0, from: nil)) } ?? false
  }

  /// Where the mouse button went up in `window` after tracking: the place of the event that
  /// ended the tracking, or the place of the pointer now if it was no such event.
  private static func releaseLocation(in window: NSWindow?) -> CGPoint? {
    guard let window else { return nil }
    if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.window === window {
      return event.locationInWindow
    }
    return window.mouseLocationOutsideOfEventStream
  }

  public override func mouseEntered(with event: NSEvent) {
    isPointerInside = true
  }

  public override func mouseExited(with event: NSEvent) {
    isPointerInside = false
  }

  public override func accessibilityChildren() -> [Any]? {
    markElements
  }

  /// Reports the block of a mark that VoiceOver pressed and scrolls it into view.
  fileprivate func pressMark(_ mark: OverviewMark) {
    let lines = displayRows.lines(ofRows: mark.rows)
    let middle = (CGFloat(lines.lowerBound) + CGFloat(lines.upperBound)) / 2
    scroll(showing: middle / CGFloat(max(displayRows.lineCount, 1)))
    delegate?.overviewBar(self, didSelectBlock: mark.block)
  }

  /// The area that the marks lie in: the track of the knob, inset from the edges.
  private var markArea: CGRect {
    let slot = rect(for: .knobSlot)
    let track = slot.isEmpty ? bounds : slot
    return CGRect(
      x: Theme.overviewMarkInset, y: track.minY, width: bounds.width - 2 * Theme.overviewMarkInset,
      height: track.height)
  }

  private var layout: OverviewLayout {
    if let cachedLayout {
      return cachedLayout
    }
    let shownMarks = marks.map { mark in
      var shown = mark
      shown.rows = displayRows.lines(ofRows: mark.rows)
      return shown
    }
    var matchLines = IndexSet()
    for row in matchRows where row < displayRows.rowCount {
      matchLines.insert(displayRows.lines(ofRows: row..<row + 1).lowerBound)
    }
    let layout = OverviewLayout(
      marks: shownMarks, matchRows: matchLines, rowCount: displayRows.lineCount,
      rowHeight: theme.rowHeight, area: markArea)
    cachedLayout = layout
    return layout
  }

  /// The marks as VoiceOver sees them, made once for each layout.
  private var markElements: [MarkElement] {
    if let cachedMarkElements {
      return cachedMarkElements
    }
    let elements = zip(marks, layout.markRects).map { mark, rect in
      MarkElement(mark: mark, frame: rect, in: self)
    }
    cachedMarkElements = elements
    return elements
  }

  private func invalidateLayout() {
    cachedLayout = nil
    cachedMarkElements = nil
    cachedCurrentBlock = nil
    needsDisplay = true
  }

  private func drawMark(_ shape: OverviewLayout.Shape) {
    let rect = shape.rect
    let radius = min(rect.width, rect.height, Theme.overviewMarkMinimumHeight) / 2
    theme.overviewMarkColor(for: shape.style).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    if shape.isOpenConflict && theme.differentiatesWithoutColor {
      // The notch tells an open conflict from a resolved one, which keeps the full width.
      Theme.backgroundColor.setFill()
      CGRect(
        x: rect.minX, y: rect.midY - Theme.overviewMarkMinimumHeight / 2,
        width: Theme.conflictNotchWidth, height: Theme.overviewMarkMinimumHeight
      ).fill()
    }
  }

  /// Draws the stroke of the matches within `span` of the bar's height, across the bar.
  ///
  /// A seam in the tone of the bar keeps the stroke clear where it crosses a mark of a similar
  /// lightness, as the marks of removed text have in the text.
  private func drawMatchStroke(_ span: Range<CGFloat>) {
    let hairline = Self.hairline(in: self)
    let stroke = CGRect(
      x: hairline, y: span.lowerBound, width: bounds.width - hairline,
      height: span.upperBound - span.lowerBound)
    let seam = stroke.insetBy(dx: 0, dy: -Theme.markSeam)
    Theme.backgroundColor.setFill()
    seam.fill()
    theme.overviewBackgroundTone.setFill()
    seam.fill(using: .sourceOver)
    theme.overviewMatchColor.setFill()
    stroke.fill(using: .sourceOver)
  }

  /// Draws the visible part as a frame across the bar, above the marks: a light fill, so that
  /// the marks keep their colors, and an outline that stands out on the bar and on any mark.
  private func drawVisibleRegion() {
    let knob = rect(for: .knob)
    guard isEnabled, !knob.isEmpty else { return }
    let hairline = Self.hairline(in: self)
    let width = Theme.visibleRegionOutlineWidth
    let region = CGRect(
      x: hairline, y: knob.minY, width: bounds.width - hairline, height: knob.height
    ).insetBy(dx: width / 2, dy: width / 2)
    let radius = Theme.visibleRegionCornerRadius
    let path = NSBezierPath(roundedRect: region, xRadius: radius, yRadius: radius)
    theme.visibleRegionFill(emphasized: isEmphasized).setFill()
    path.fill()
    theme.visibleRegionOutline(emphasized: isEmphasized).setStroke()
    path.lineWidth = width
    path.stroke()
  }

  /// Draws the triangle at the middle of the marks of the current block: of its one mark, or of
  /// the marks of its parts one below the other in a single column.
  private func drawCurrentBlockIndicator(_ layout: OverviewLayout) {
    guard let currentBlock else { return }
    if cachedCurrentBlock != currentBlock {
      cachedCurrentBlockRect = zip(marks, layout.markRects).filter { $0.0.block == currentBlock }
        .map(\.1).reduce(nil) { $0?.union($1) ?? $1 }
      cachedCurrentBlock = currentBlock
    }
    guard let rect = cachedCurrentBlockRect else { return }
    let middle = rect.midY
    let height = Theme.currentBlockIndicatorHeight
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 0, y: middle - height / 2))
    path.line(to: CGPoint(x: height / 2, y: middle))
    path.line(to: CGPoint(x: 0, y: middle + height / 2))
    path.close()
    NSColor.labelColor.setFill()
    path.fill()
  }

  /// Has the pane scroll so that the place `fraction` of its text, from 0 at its top to 1 at its
  /// end, comes to its reading line.
  ///
  /// The place comes from the rows, as the marks do, not from the knob, which keeps a minimum
  /// length in long texts.
  private func scroll(showing fraction: CGFloat) {
    let proportion = CGFloat(knobProportion)
    guard isEnabled, proportion < 1 else { return }
    doubleValue = min(max((fraction - Theme.readingLine * proportion) / (1 - proportion), 0), 1)
    isPlacingKnob = true
    defer { isPlacingKnob = false }
    sendAction(action, to: target)
  }

  /// The width of a line one pixel thin on the screen of `view`.
  private static func hairline(in view: NSView) -> CGFloat {
    1 / (view.window?.backingScaleFactor ?? 2)
  }
}

/// A mark of the overview bar as VoiceOver sees it: a button that scrolls to its block.
private final class MarkElement: NSAccessibilityElement {
  private let mark: OverviewMark
  private weak var bar: OverviewBar?

  init(mark: OverviewMark, frame rect: CGRect, in bar: OverviewBar) {
    self.mark = mark
    self.bar = bar
    super.init()
    setAccessibilityRole(.button)
    setAccessibilityLabel(mark.accessibilityLabel)
    setAccessibilityParent(bar)
    setAccessibilityFrameInParentSpace(rect)
  }

  override func accessibilityPerformPress() -> Bool {
    guard let bar else { return false }
    let mark = mark
    // Accessibility calls in on the main thread.
    MainActor.assumeIsolated { bar.pressMark(mark) }
    return true
  }
}
