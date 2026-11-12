import AppKit
import MergeModel
import PaneKit

/// The panes of a merge window and how they are laid out: A, Base and B side by side and equally
/// wide above, the result across the full width below.
///
/// The controller only arranges; what the panes show is set from outside.
@MainActor
final class SessionSplitViewController: NSSplitViewController {
  /// The panes of the inputs, in the order A, Base, B, as many as take part.
  let sourcePanes: [(role: Role, pane: PaneView)]

  /// The result pane.
  let resultPane: PaneView

  private let sourcesController = NSSplitViewController()

  /// Creates the panes for `roles`, drawn with `theme`.
  init(roles: [Role], theme: Theme) {
    sourcePanes = roles.map { ($0, PaneView(theme: theme)) }
    resultPane = PaneView(theme: theme)
    super.init(nibName: nil, bundle: nil)
    splitView.isVertical = false
    sourcesController.splitView.isVertical = true
    for (_, pane) in sourcePanes {
      sourcesController.addSplitViewItem(
        NSSplitViewItem(viewController: PaneItemController(pane: pane)))
    }
    let sourcesItem = NSSplitViewItem(viewController: sourcesController)
    sourcesItem.minimumThickness = WindowMetrics.minimumPaneHeight
    addSplitViewItem(sourcesItem)
    let resultItem = NSSplitViewItem(viewController: PaneItemController(pane: resultPane))
    resultItem.minimumThickness = WindowMetrics.minimumPaneHeight
    addSplitViewItem(resultItem)
  }

  /// Gives each source pane the least width its content needs, so that the dividers between
  /// them stay usable; call it once the panes have their content.
  func updateMinimumWidths() {
    for (item, (_, pane)) in zip(sourcesController.splitViewItems, sourcePanes) {
      item.minimumThickness = pane.minimumWidth
    }
  }

  /// Draws the panes with `theme`.
  func apply(_ theme: Theme) {
    for (_, pane) in sourcePanes {
      pane.theme = theme
    }
    resultPane.theme = theme
  }

  /// Split view controllers of a window are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The narrowest the panes get together: each source pane at its least width, with the
  /// dividers between them.
  var minimumWidth: CGFloat {
    let divider = sourcesController.splitView.dividerThickness
    let panes = sourcePanes.map(\.pane.minimumWidth).reduce(0, +)
    return max(panes + divider * CGFloat(sourcePanes.count - 1), resultPane.minimumWidth)
  }

  /// The least height of the panes together: the sources and the result each at their least
  /// height, with the divider between them.
  var minimumHeight: CGFloat {
    view.layoutSubtreeIfNeeded()
    return view.fittingSize.height
  }

  /// Places the dividers as a new window has them: the source panes equally wide, and above
  /// the result their share of the height.
  ///
  /// - Precondition: The view is in its window, at the window's size.
  func placeDividers() {
    view.layoutSubtreeIfNeeded()
    splitView.setPosition(
      (splitView.bounds.height * WindowMetrics.sourcesFraction).rounded(), ofDividerAt: 0)
    let sources = sourcesController.splitView
    sources.layoutSubtreeIfNeeded()
    let divider = sources.dividerThickness
    let paneWidth =
      (sources.bounds.width - divider * CGFloat(sourcePanes.count - 1))
      / CGFloat(sourcePanes.count)
    for index in 0..<sourcePanes.count - 1 {
      sources.setPosition(
        (paneWidth * CGFloat(index + 1) + divider * CGFloat(index)).rounded(), ofDividerAt: index)
    }
  }

}

/// The view controller of one pane in the split view: the pane fills the item.
@MainActor
private final class PaneItemController: NSViewController {
  private let pane: PaneView

  init(pane: PaneView) {
    self.pane = pane
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let container = NSView()
    pane.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(pane)
    NSLayoutConstraint.activate([
      pane.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
      pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    view = container
  }
}
