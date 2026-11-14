import AppKit
import MergeModel
import PaneKit
import SwiftUI

/// The panes of a session window and how they are laid out: the inputs side by side and equally
/// wide, A, Base and B in a merge, and below them in a merge the result across the full width,
/// each pane with its header.
///
/// The headers are accessories at the top of the split view items, as the system lays them out,
/// with a hard edge, since dense code would blur under a soft one. The controller only arranges;
/// what the panes show is set from outside.
@MainActor
final class SessionSplitViewController: NSSplitViewController {
  /// The panes of the inputs from left to right, each with the input it shows now.
  private(set) var sourcePanes: [(role: Role, pane: PaneView)]

  /// The result pane, which only a merge has.
  let resultPane: PaneView?

  /// The pane of `role`, if the input takes part.
  func sourcePane(_ role: Role) -> PaneView? {
    sourcePanes.first { $0.role == role }?.pane
  }

  /// Supplies the context menus of the headers; the controller does not retain it.
  weak var delegate: (any SessionLayoutDelegate)?

  /// Carries out a choice of the pop-up menus of the result header.
  var chooseResultFormat: (ResultFormatChoice) -> Void = { _ in }

  private let sourcesController = PanesSplitViewController()
  private var viewInPlaceOfTheLines: NSView?
  private let sourceHeaderViews: [HeaderHostingView<SideHeaderView>]
  private let resultHeaderView: HeaderHostingView<ResultHeaderView>?

  /// Creates the panes for the inputs of `headers`, from left to right, and for the result of
  /// `resultHeader` below them if there is one, drawn with `theme`.
  init(headers: [SideHeader], resultHeader: ResultHeader?, theme: Theme) {
    sourcePanes = headers.map { ($0.role, PaneView(theme: theme)) }
    resultPane = resultHeader.map { _ in PaneView(theme: theme) }
    sourceHeaderViews = headers.map {
      HeaderHostingView(rootView: SideHeaderView(header: $0, theme: theme), role: $0.role)
    }
    resultHeaderView = resultHeader.map {
      HeaderHostingView(
        rootView: ResultHeaderView(header: $0, callerIsGone: false) { _ in }, role: nil)
    }
    super.init(nibName: nil, bundle: nil)
    if let resultHeaderView {
      resultHeaderView.rootView = makeResultHeaderView(
        header: resultHeaderView.rootView.header, callerIsGone: false)
    }
    for headerView in sourceHeaderViews {
      headerView.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
    }
    resultHeaderView?.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
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
    if let resultPane, let resultHeaderView {
      let resultItem = NSSplitViewItem(viewController: PaneItemController(pane: resultPane))
      resultItem.minimumThickness = WindowMetrics.minimumPaneHeight
      resultItem.addTopAlignedAccessoryViewController(Self.accessory(resultHeaderView))
      addSplitViewItem(resultItem)
    }
  }

  /// Shows the inputs of `headers` in the panes from left to right, each below its header; the
  /// panes keep their widths and places.
  ///
  /// - Precondition: `headers` has one header for each pane.
  func show(_ headers: [SideHeader]) {
    precondition(headers.count == sourcePanes.count, "Every pane needs a header")
    for (index, header) in headers.enumerated() {
      sourcePanes[index].role = header.role
      let headerView = sourceHeaderViews[index]
      headerView.role = header.role
      headerView.rootView = SideHeaderView(header: header, theme: headerView.rootView.theme)
    }
  }

  /// Shows `view` across the panes side by side, below their headers, in place of their lines,
  /// which a comparison does whose files cannot be compared.
  func showInPlaceOfTheLines(_ view: NSView) {
    viewInPlaceOfTheLines?.removeFromSuperview()
    viewInPlaceOfTheLines = view
    for (_, pane) in sourcePanes {
      pane.isHidden = true
    }
    guard let header = sourceHeaderViews.first else { return }
    let container = sourcesController.view
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: header.bottomAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }

  /// Shows the lines in the panes again, in place of the view that said why they could not be
  /// shown.
  func showLinesAgain() {
    viewInPlaceOfTheLines?.removeFromSuperview()
    viewInPlaceOfTheLines = nil
    for (_, pane) in sourcePanes {
      pane.isHidden = false
    }
  }

  /// The panes have no sidebar: Show Sidebar belongs to the split view around them, in a window
  /// that compares several files, and passes them by on its way along the responder chain.
  override func responds(to selector: Selector!) -> Bool {
    selector == #selector(toggleSidebar(_:)) ? false : super.responds(to: selector)
  }

  /// Whether the pane of the base is in view; while it is hidden, A and B share its width.
  ///
  /// - Precondition: The merge has a base, if the pane is to be hidden.
  var showsBase: Bool {
    get { baseItem.map { !$0.isCollapsed } ?? false }
    set {
      guard let baseItem else {
        precondition(!newValue, "A merge without a base has no base pane to show")
        return
      }
      baseItem.isCollapsed = !newValue
      if newValue {
        placeSourceDividers()
      }
    }
  }

  /// Whether the result has the whole window, with the panes above it collapsed.
  ///
  /// - Precondition: The window has a result, if it is to be maximized.
  var maximizesResult: Bool {
    get { resultPane != nil && splitViewItems.first?.isCollapsed == true }
    set {
      precondition(resultPane != nil || !newValue, "Only a window with a result maximizes it")
      splitViewItems.first?.isCollapsed = newValue
    }
  }

  /// The split view item of the pane of the base, if the merge has one.
  private var baseItem: NSSplitViewItem? {
    sourcePanes.firstIndex { $0.role == .base }.map { sourcesController.splitViewItems[$0] }
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
    resultPane?.theme = theme
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

  /// The narrowest the panes get together: each source pane in view at its least width, with
  /// the dividers between them, and the result no narrower than it needs.
  var minimumWidth: CGFloat {
    let divider = sourcesController.splitView.dividerThickness
    let shown = zip(sourcesController.splitViewItems, sourcePanes).filter { !$0.0.isCollapsed }
    let panes = shown.map(\.1.pane.minimumWidth).reduce(0, +)
    return max(
      panes + divider * CGFloat(max(shown.count - 1, 0)), resultPane?.minimumWidth ?? 0)
  }

  /// The least height of the panes together: the sources and the result, if there is one, each
  /// at their least height below their headers, with the divider between them.
  var minimumHeight: CGFloat {
    view.layoutSubtreeIfNeeded()
    return view.fittingSize.height
  }

  /// Shows below the result header that Git no longer waits for the merge; a comparison, which
  /// has nothing to save, does not say so.
  func showCallerIsGone() {
    guard let resultHeaderView else { return }
    resultHeaderView.rootView = makeResultHeaderView(
      header: resultHeaderView.rootView.header, callerIsGone: true)
  }

  /// The header of the result, if there is one.
  var resultHeader: ResultHeader? {
    resultHeaderView?.rootView.header
  }

  /// Shows `header` above the result.
  func show(_ header: ResultHeader) {
    guard let resultHeaderView, resultHeaderView.rootView.header != header else { return }
    resultHeaderView.rootView = makeResultHeaderView(
      header: header, callerIsGone: resultHeaderView.rootView.callerIsGone)
  }

  private func makeResultHeaderView(header: ResultHeader, callerIsGone: Bool) -> ResultHeaderView {
    ResultHeaderView(header: header, callerIsGone: callerIsGone) { [weak self] choice in
      self?.chooseResultFormat(choice)
    }
  }

  /// Places the dividers as a new window has them: the source panes equally wide, and above
  /// the result their share of the height.
  ///
  /// - Precondition: The view is in its window, at the window's size.
  func placeDividers() {
    view.layoutSubtreeIfNeeded()
    if resultPane != nil {
      splitView.setPosition(
        (splitView.bounds.height * WindowMetrics.sourcesFraction).rounded(), ofDividerAt: 0)
    }
    placeSourceDividers()
  }

  /// Makes the source panes equally wide again.
  private func placeSourceDividers() {
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
  var role: Role?

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

/// The split view of the panes side by side, which passes Show Sidebar by like the split view
/// around it.
@MainActor
private final class PanesSplitViewController: NSSplitViewController {
  override func responds(to selector: Selector!) -> Bool {
    selector == #selector(toggleSidebar(_:)) ? false : super.responds(to: selector)
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
