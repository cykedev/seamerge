import AppKit

/// A pane: the text of one side on the row grid, with line numbers and markers in its gutter.
///
/// The pane shows what it is given and knows neither the engine nor the merge model. Row *r* of
/// the content lies at `r × theme.rowHeight` from the top of the text, in every pane alike.
public final class PaneView: NSView {
  /// The fonts, metrics and colors of the pane.
  public var theme: Theme {
    didSet { show() }
  }

  /// What the pane shows.
  ///
  /// - Precondition: The content has one line number and one line ending per row.
  public var content: PaneContent = .empty {
    didSet { show() }
  }

  /// The index of the current block in the content's blocks, or `nil` if there is none.
  ///
  /// The rows of the current block are tinted more strongly and its line-number cells filled.
  public var currentBlock: Int? {
    get { textView.currentBlock }
    set {
      textView.setCurrentBlock(newValue)
      gutterView.currentBlock = textView.currentBlock
    }
  }

  /// Supplies the changed runs within the lines of the blocks; the pane does not retain it.
  public var highlightProvider: (any PaneHighlightProvider)? {
    get { textView.highlightProvider }
    set { textView.highlightProvider = newValue }
  }

  /// Whether spaces, tabs and line endings show as quiet symbols.
  ///
  /// The symbols are drawn only: they are neither copied nor read by VoiceOver.
  public var showsInvisibles: Bool {
    get { textView.showsInvisibles }
    set { textView.showsInvisibles = newValue }
  }

  /// The overview bar that serves as the pane's vertical scroller, beside its right edge, or
  /// `nil` for a pane without one, which scrolls along with a pane that has it.
  ///
  /// The bar sits beside the scroll view rather than in it, so that the scroll view shows its
  /// horizontal scroller in the style that the user chose, as in every other pane.
  public var overviewBar: OverviewBar? {
    didSet {
      guard overviewBar !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let overviewBar {
        overviewBar.target = self
        overviewBar.action = #selector(overviewBarDidScroll(_:))
        overviewBar.rowCount = content.lineNumbers.count
        addSubview(overviewBar)
      }
      needsLayout = true
    }
  }

  /// The view that shows the text, for selection and the find bar.
  public var documentView: NSTextView { textView }

  /// The view that clips the text to the visible part, whose bounds origin is the scroll
  /// position.
  var clipView: NSClipView { scrollView.contentView }

  /// How far the text scrolls vertically.
  var verticalScrollRange: CGFloat {
    max(textView.frame.height - clipView.bounds.height, 0)
  }

  /// Moves the top left corner of the visible part of the text to `origin`, as given.
  func scroll(to origin: CGPoint) {
    clipView.scroll(to: origin)
    scrollView.reflectScrolledClipView(clipView)
  }

  private let textView = PaneTextView(usingTextLayoutManager: true)
  private let gutterView = GutterView()
  private let scrollView = PaneScrollView()

  /// Creates an empty pane.
  public init(theme: Theme = Theme()) {
    self.theme = theme
    super.init(frame: .zero)
    textView.configure(theme: theme)
    scrollView.documentView = textView
    NotificationCenter.default.addObserver(
      self, selector: #selector(clipViewBoundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView)
    gutterView.removalRows = { [weak textView] rows in textView?.removalRows(in: rows) ?? [] }
    addSubview(gutterView)
    addSubview(scrollView)
    show()
  }

  /// Panes are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  public override var isFlipped: Bool { true }

  public override func layout() {
    super.layout()
    let gutterWidth = gutterView.fittingWidth
    let barWidth = overviewBar == nil ? 0 : Theme.overviewBarWidth
    gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    scrollView.frame = CGRect(
      x: gutterWidth, y: 0, width: max(bounds.width - gutterWidth - barWidth, 0),
      height: bounds.height)
    overviewBar?.frame = CGRect(
      x: bounds.width - barWidth, y: 0, width: barWidth, height: bounds.height)
    scrollView.tile()
    let visibleWidth = clipView.bounds.width
    let range = max(textView.textWidth - visibleWidth, 0)
    let hasHorizontalScroller = range > 0
    if scrollView.hasHorizontalScroller != hasHorizontalScroller {
      scrollView.hasHorizontalScroller = hasHorizontalScroller
      scrollView.tile()
    }
    textView.setFrameSize(
      CGSize(
        width: visibleWidth + range, height: CGFloat(content.lineNumbers.count) * theme.rowHeight))
    textDidScroll()
  }

  /// Hands scrolling over the gutter and the overview bar to the text.
  public override func scrollWheel(with event: NSEvent) {
    scrollView.scrollWheel(with: event)
  }

  private func show() {
    textView.show(content, theme: theme)
    gutterView.theme = theme
    gutterView.content = content
    gutterView.currentBlock = textView.currentBlock
    overviewBar?.rowCount = content.lineNumbers.count
    needsLayout = true
  }

  @objc private func clipViewBoundsDidChange(_ notification: Notification) {
    textDidScroll()
  }

  /// Moves the gutter and the overview bar along with the text.
  private func textDidScroll() {
    let visible = clipView.bounds
    gutterView.scrollOffset = visible.minY
    guard let overviewBar else { return }
    let height = textView.frame.height
    overviewBar.isEnabled = height > visible.height
    overviewBar.knobProportion = height > 0 ? min(visible.height / height, 1) : 1
    overviewBar.doubleValue = verticalScrollRange > 0 ? visible.minY / verticalScrollRange : 0
  }

  /// Scrolls the text to the place of the overview bar's knob, or by a page.
  @objc private func overviewBarDidScroll(_ sender: OverviewBar) {
    let visible = clipView.bounds
    let y: CGFloat =
      switch sender.hitPart {
      case .decrementPage where !sender.isPlacingKnob: visible.minY - visible.height
      case .incrementPage where !sender.isPlacingKnob: visible.minY + visible.height
      default: sender.doubleValue * verticalScrollRange
      }
    scroll(to: CGPoint(x: visible.minX, y: min(max(y, 0), verticalScrollRange).rounded()))
  }
}
