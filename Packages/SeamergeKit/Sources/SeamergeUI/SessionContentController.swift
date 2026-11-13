import AppKit

/// The content of a session window: the panes, and below them across the full width the footer
/// in the bottom border of the window, as long as the footer is shown.
@MainActor
final class SessionContentController: NSViewController {
  /// The panes of the window and how they are laid out.
  let layout: SessionSplitViewController

  /// The footer below the panes.
  let footer: SessionFooterView

  private var footerHeight: NSLayoutConstraint?

  /// Creates the content of `layout` with `footer` below it.
  init(layout: SessionSplitViewController, footer: SessionFooterView) {
    self.layout = layout
    self.footer = footer
    super.init(nibName: nil, bundle: nil)
    addChild(layout)
  }

  /// Content controllers of a window are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let container = NSView()
    let panes = layout.view
    panes.translatesAutoresizingMaskIntoConstraints = false
    footer.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panes)
    container.addSubview(footer)
    let footerHeight = footer.heightAnchor.constraint(equalToConstant: WindowMetrics.footerHeight)
    self.footerHeight = footerHeight
    NSLayoutConstraint.activate([
      panes.topAnchor.constraint(equalTo: container.topAnchor),
      panes.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      panes.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      panes.bottomAnchor.constraint(equalTo: footer.topAnchor),
      footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      footerHeight,
    ])
    view = container
  }

  /// Whether the footer is in view; the window draws its bottom border only while it is.
  var showsFooter: Bool {
    get { !footer.isHidden }
    set {
      loadViewIfNeeded()
      footer.isHidden = !newValue
      footerHeight?.constant = newValue ? WindowMetrics.footerHeight : 0
      updateBottomBorder()
    }
  }

  /// Gives the window a bottom border as tall as the footer, or none while it is hidden.
  private func updateBottomBorder() {
    guard let window = view.window else { return }
    window.setAutorecalculatesContentBorderThickness(false, for: .minY)
    window.setContentBorderThickness(showsFooter ? WindowMetrics.footerHeight : 0, for: .minY)
  }

  /// The height that the footer takes from the window now.
  var footerHeightInView: CGFloat {
    showsFooter ? WindowMetrics.footerHeight : 0
  }
}
