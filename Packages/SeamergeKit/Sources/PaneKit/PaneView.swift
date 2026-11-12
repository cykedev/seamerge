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

  /// The view that shows the text, for selection and the find bar.
  public var documentView: NSTextView { textView }

  private let textView = PaneTextView(usingTextLayoutManager: true)
  private let gutterView = GutterView()
  private let scrollView = NSScrollView()

  /// Creates an empty pane.
  public init(theme: Theme = Theme()) {
    self.theme = theme
    super.init(frame: .zero)
    textView.configure(theme: theme)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Theme.backgroundColor
    scrollView.documentView = textView
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(textDidScroll(_:)), name: NSView.boundsDidChangeNotification,
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
    gutterView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    scrollView.frame = CGRect(
      x: gutterWidth, y: 0, width: max(bounds.width - gutterWidth, 0), height: bounds.height)
    textView.setFrameSize(textView.fittingSize(visibleWidth: scrollView.contentSize.width))
  }

  private func show() {
    textView.show(content, theme: theme)
    gutterView.theme = theme
    gutterView.content = content
    gutterView.currentBlock = textView.currentBlock
    needsLayout = true
  }

  @objc private func textDidScroll(_ notification: Notification) {
    gutterView.scrollOffset = scrollView.contentView.bounds.minY
  }
}
