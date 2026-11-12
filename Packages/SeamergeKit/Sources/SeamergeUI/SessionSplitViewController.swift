import AppKit
import MergeModel
import PaneKit
import SwiftUI

/// The panes of a merge window and how they are laid out: A, Base and B side by side and equally
/// wide above, the result across the full width below, each with its header.
///
/// The headers are accessories at the top of the split view items, as the system lays them out,
/// with a hard edge, since dense code would blur under a soft one. The controller only arranges;
/// what the panes show is set from outside.
@MainActor
final class SessionSplitViewController: NSSplitViewController {
  /// The panes of the inputs, in the order A, Base, B, as many as take part.
  let sourcePanes: [(role: Role, pane: PaneView)]

  /// The result pane.
  let resultPane: PaneView

  /// Supplies the context menus of the headers; the controller does not retain it.
  weak var delegate: (any SessionLayoutDelegate)?

  private let sourcesController = NSSplitViewController()
  private let sourceHeaderViews: [HeaderHostingView<SideHeaderView>]
  private let resultHeaderView: HeaderHostingView<ResultHeaderView>

  /// Creates the panes for the inputs of `headers`, drawn with `theme`.
  init(headers: [SideHeader], resultHeader: ResultHeader, theme: Theme) {
    sourcePanes = headers.map { ($0.role, PaneView(theme: theme)) }
    resultPane = PaneView(theme: theme)
    sourceHeaderViews = headers.map {
      HeaderHostingView(rootView: SideHeaderView(header: $0, theme: theme), role: $0.role)
    }
    resultHeaderView = HeaderHostingView(
      rootView: ResultHeaderView(header: resultHeader, callerIsGone: false), role: nil)
    super.init(nibName: nil, bundle: nil)
    for headerView in sourceHeaderViews {
      headerView.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
    }
    resultHeaderView.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
    splitView.isVertical = false
    sourcesController.splitView.isVertical = true
    for (headerView, (_, pane)) in zip(sourceHeaderViews, sourcePanes) {
      let item = NSSplitViewItem(viewController: PaneItemController(pane: pane))
      item.addTopAlignedAccessoryViewController(Self.accessory(headerView))
      sourcesController.addSplitViewItem(item)
    }
    let sourcesItem = NSSplitViewItem(viewController: sourcesController)
    // The headers of the sources lie within this item; the result's lies outside its own.
    sourcesItem.minimumThickness = WindowMetrics.minimumPaneHeight + WindowMetrics.headerHeight
    addSplitViewItem(sourcesItem)
    let resultItem = NSSplitViewItem(viewController: PaneItemController(pane: resultPane))
    resultItem.minimumThickness = WindowMetrics.minimumPaneHeight
    resultItem.addTopAlignedAccessoryViewController(Self.accessory(resultHeaderView))
    addSplitViewItem(resultItem)
  }

  /// Gives each source pane the least width its content needs, so that the dividers between
  /// them stay usable; call it once the panes have their content.
  func updateMinimumWidths() {
    for (item, (_, pane)) in zip(sourcesController.splitViewItems, sourcePanes) {
      item.minimumThickness = pane.minimumWidth
    }
  }

  /// Draws the panes and headers with `theme`.
  func apply(_ theme: Theme) {
    for (_, pane) in sourcePanes {
      pane.theme = theme
    }
    resultPane.theme = theme
    for headerView in sourceHeaderViews {
      headerView.rootView = SideHeaderView(header: headerView.rootView.header, theme: theme)
    }
  }

  private func headerMenu(for role: Role?) -> NSMenu? {
    delegate?.layout(self, menuForHeaderOf: role)
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
  /// height below their headers, with the divider between them.
  var minimumHeight: CGFloat {
    view.layoutSubtreeIfNeeded()
    return view.fittingSize.height
  }

  /// Shows below the result header that Git no longer waits for the merge.
  func showCallerIsGone() {
    resultHeaderView.rootView = ResultHeaderView(
      header: resultHeaderView.rootView.header, callerIsGone: true)
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

  /// The accessory that shows `header` at the top of a split view item, with a hard edge.
  private static func accessory(_ header: NSView) -> NSSplitViewItemAccessoryViewController {
    let accessory = NSSplitViewItemAccessoryViewController()
    accessory.view = header
    // The header keeps its own height of 28 points rather than the system's taller insets.
    accessory.automaticallyAppliesContentInsets = false
    accessory.preferredScrollEdgeEffectStyle = .hard
    return accessory
  }
}

/// Supplies what the layout of a window shows on demand.
@MainActor
protocol SessionLayoutDelegate: AnyObject {
  /// The context menu of the header of the pane of `role`, or of the result for `nil`, or `nil`
  /// for none.
  func layout(_ layout: SessionSplitViewController, menuForHeaderOf role: Role?) -> NSMenu?
}

/// A header hosted in AppKit, with a context menu of its own.
@MainActor
final class HeaderHostingView<Content: View>: NSHostingView<Content> {
  /// The input of the pane below, or `nil` for the result.
  let role: Role?

  /// Supplies the context menu for the role of the header.
  var menuProvider: (Role?) -> NSMenu? = { _ in nil }

  init(rootView: Content, role: Role?) {
    self.role = role
    super.init(rootView: rootView)
  }

  required init(rootView: Content) {
    role = nil
    super.init(rootView: rootView)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    menuProvider(role)
  }
}

/// The view controller of one pane in the split view: the pane fills the item below its header.
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
