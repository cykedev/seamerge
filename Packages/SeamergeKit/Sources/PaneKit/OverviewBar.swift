import AppKit

/// Receives the clicks on the marks of an overview bar.
@MainActor
public protocol OverviewBarDelegate: AnyObject {
  /// Tells the delegate that the mark of `block` was clicked, or pressed with VoiceOver.
  func overviewBar(_ overviewBar: OverviewBar, didSelectBlock block: Int)
}

/// The vertical scroller of a pane that also shows where the text changes: a mark for each
/// block, the visible part of the text as a light area, the current block with a small triangle.
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

  /// The index of the current block, whose mark the triangle points at, or `nil` if there is
  /// none.
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

  public override func setFrameSize(_ newSize: NSSize) {
    let changed = newSize != frame.size
    super.setFrameSize(newSize)
    if changed {
      invalidateLayout()
    }
  }

  public override func draw(_ dirtyRect: NSRect) {
    Theme.backgroundColor.setFill()
    bounds.fill()
    theme.overviewBackgroundTone.setFill()
    bounds.fill(using: .sourceOver)
    NSColor.separatorColor.setFill()
    CGRect(x: 0, y: 0, width: Self.hairline(in: self), height: bounds.height).fill(
      using: .sourceOver)
    let layout = layout
    for shape in layout.shapes {
      drawMark(shape)
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
    super.mouseDown(with: event)
    if let block, hitPart != .decrementPage, hitPart != .incrementPage {
      delegate?.overviewBar(self, didSelectBlock: block)
    }
  }

  public override func accessibilityChildren() -> [Any]? {
    markElements
  }

  /// Reports the block of a mark that VoiceOver pressed and scrolls it into view.
  fileprivate func pressMark(_ mark: OverviewMark) {
    let rows = displayRows.displayRows(ofRows: mark.rows)
    let middle = (CGFloat(rows.lowerBound) + CGFloat(rows.upperBound)) / 2
    scroll(showing: middle / CGFloat(max(displayRows.count, 1)))
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
      shown.rows = displayRows.displayRows(ofRows: mark.rows)
      return shown
    }
    let layout = OverviewLayout(marks: shownMarks, rowCount: displayRows.count, area: markArea)
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

  private func drawVisibleRegion() {
    let knob = rect(for: .knob)
    guard isEnabled, !knob.isEmpty else { return }
    let hairline = Self.hairline(in: self)
    let region = CGRect(
      x: hairline, y: knob.minY, width: bounds.width - hairline, height: knob.height
    ).insetBy(dx: hairline / 2, dy: hairline / 2)
    let path = NSBezierPath(roundedRect: region, xRadius: 2, yRadius: 2)
    theme.visibleRegionFill.setFill()
    path.fill()
    theme.visibleRegionOutline.setStroke()
    path.lineWidth = hairline
    path.stroke()
  }

  private func drawCurrentBlockIndicator(_ layout: OverviewLayout) {
    guard
      let currentBlock,
      let index = marks.firstIndex(where: { $0.block == currentBlock })
    else { return }
    let middle = layout.markRects[index].midY
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
