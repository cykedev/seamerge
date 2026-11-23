import AppKit
import MergeModel
import PaneKit
import SwiftUI

/// The panes of a session window and how they are laid out: the inputs side by side and equally
/// wide, A, Base and B in a merge, and below them in a merge the result across the full width,
/// each pane with its header; a comparison shows its two files in a single column instead, on
/// demand, in a pane of its own below a header that names both.
///
/// The headers are accessories at the top of the split view items, as the system lays them out,
/// with a hard edge, since dense code would blur under a soft one. Between the inputs lie
/// hairlines, or seams while the panes connect their changes with bands. The controller only
/// arranges; what the panes show is set from outside.
@MainActor
final class SessionSplitViewController: NSSplitViewController {
  /// The panes of the inputs from left to right, each with the input it shows now.
  private(set) var sourcePanes: [(role: Role, pane: PaneView)]

  /// The result pane, which only a merge has.
  let resultPane: PaneView?

  /// The pane that shows both files of a comparison in a single column, which only a comparison
  /// of two files has.
  let columnPane: PaneView?

  /// The pane of `role`, if the input takes part.
  func sourcePane(_ role: Role) -> PaneView? {
    sourcePanes.first { $0.role == role }?.pane
  }

  /// Supplies the context menus of the headers; the controller does not retain it.
  weak var delegate: (any SessionLayoutDelegate)?

  /// Carries out a choice of the pop-up menus of the result header.
  var chooseResultFormat: (ResultFormatChoice) -> Void = { _ in }

  private let sourcesController = PanesSplitViewController()
  private let sourcesItem: NSSplitViewItem
  private var viewInPlaceOfTheLines: NSView?
  private let sourceHeaderViews: [HeaderHostingView<SideHeaderView>]
  private let resultHeaderView: HeaderHostingView<ResultHeaderView>?
  private let columnItem: NSSplitViewItem?
  private let columnHeaderView: HeaderHostingView<ColumnHeaderView>?

  /// Creates the panes for the inputs of `headers`, from left to right, and for the result of
  /// `resultHeader` below them if there is one, drawn with `theme`; without a result, two
  /// inputs get a pane for the single column as well.
  init(headers: [SideHeader], resultHeader: ResultHeader?, theme: Theme) {
    sourcePanes = headers.map { ($0.role, PaneView(theme: theme)) }
    resultPane = resultHeader.map { _ in PaneView(theme: theme) }
    let hasColumn = resultHeader == nil && headers.count == 2
    columnPane = hasColumn ? PaneView(theme: theme) : nil
    columnHeaderView =
      hasColumn
      ? HeaderHostingView(rootView: ColumnHeaderView(headers: headers, theme: theme), role: nil)
      : nil
    sourceHeaderViews = headers.map {
      HeaderHostingView(rootView: SideHeaderView(header: $0, theme: theme), role: $0.role)
    }
    resultHeaderView = resultHeader.map {
      HeaderHostingView(
        rootView: ResultHeaderView(header: $0, callerIsGone: false) { _ in }, role: nil)
    }
    sourcesItem = NSSplitViewItem(viewController: sourcesController)
    columnItem = columnPane.map { NSSplitViewItem(viewController: PaneItemController(pane: $0)) }
    super.init(nibName: nil, bundle: nil)
    if let columnItem, let columnHeaderView {
      columnItem.minimumThickness = WindowMetrics.minimumPaneHeight
      columnItem.addTopAlignedAccessoryViewController(Self.accessory(columnHeaderView))
    }
    if let resultHeaderView {
      resultHeaderView.rootView = makeResultHeaderView(
        header: resultHeaderView.rootView.header, callerIsGone: false)
    }
    for headerView in sourceHeaderViews {
      headerView.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
    }
    resultHeaderView?.menuProvider = { [weak self] role in self?.headerMenu(for: role) }
    splitView.isVertical = false
    sourcesController.splitView = SeamSplitView()
    sourcesController.splitView.isVertical = true
    for (headerView, (_, pane)) in zip(sourceHeaderViews, sourcePanes) {
      let item = NSSplitViewItem(viewController: PaneItemController(pane: pane))
      item.addTopAlignedAccessoryViewController(Self.accessory(headerView))
      sourcesController.addSplitViewItem(item)
    }
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
    if let columnHeaderView {
      columnHeaderView.rootView = ColumnHeaderView(
        headers: headers, theme: columnHeaderView.rootView.theme)
    }
  }

  /// Whether the two files of a comparison show in a single column, in place of the panes side
  /// by side, which keep their content, widths and places meanwhile.
  ///
  /// - Precondition: The window has a single column, if it is to show it.
  var showsSingleColumn: Bool {
    get { columnItem.map(splitViewItems.contains) ?? false }
    set {
      guard newValue != showsSingleColumn else { return }
      guard let columnItem else {
        preconditionFailure("Only a comparison of two files shows a single column")
      }
      let (shown, hidden) = newValue ? (columnItem, sourcesItem) : (sourcesItem, columnItem)
      removeSplitViewItem(hidden)
      insertSplitViewItem(shown, at: 0)
      if let viewInPlaceOfTheLines {
        showInPlaceOfTheLines(viewInPlaceOfTheLines)
      }
      view.layoutSubtreeIfNeeded()
    }
  }

  /// Shows `view` across the panes side by side, below their headers, in place of their lines,
  /// which a comparison does whose files cannot be compared.
  func showInPlaceOfTheLines(_ view: NSView) {
    viewInPlaceOfTheLines?.removeFromSuperview()
    viewInPlaceOfTheLines = view
    for pane in sourcePanes.map(\.pane) + [columnPane].compactMap(\.self) {
      pane.isHidden = true
    }
    let shown: (header: NSView, container: NSView)? =
      if showsSingleColumn, let columnHeaderView, let columnItem {
        (columnHeaderView, columnItem.viewController.view)
      } else {
        sourceHeaderViews.first.map { ($0, sourcesController.view) }
      }
    guard let (header, container) = shown else { return }
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
    for pane in sourcePanes.map(\.pane) + [columnPane].compactMap(\.self) {
      pane.isHidden = false
    }
  }

  /// The panes have no sidebar: Show Sidebar belongs to the split view around them, in a window
  /// that compares several files, and passes them by on its way along the responder chain.
  override func responds(to selector: Selector!) -> Bool {
    selector == #selector(toggleSidebar(_:)) ? false : super.responds(to: selector)
  }

  /// Whether the dividers between the panes side by side are seams that connect their changes
  /// with bands, wide enough to show them, rather than hairlines.
  ///
  /// The panes keep their share of the width; each seam stays a divider that can be dragged.
  /// The seams lie between the panes in view: while the base is hidden, one connects A with B.
  var showsSeams = false {
    didSet {
      if showsSeams != oldValue {
        placeSeamsBetweenShownPanes()
      }
    }
  }

  /// The sides of a comparison that changes may be copied to, which put a seam with buttons
  /// between the panes also while they line up their rows; none at first.
  var copyDirections: Set<PaneSeam.CopyDirection> = [] {
    didSet {
      if copyDirections != oldValue {
        placeSeamsBetweenShownPanes()
      }
    }
  }

  /// Gives the panes in view a seam between each two neighbors while they show seams or changes
  /// may be copied, and takes the seams away otherwise; seams that stay between the same panes
  /// stay as they are, and take how they show now.
  private func placeSeamsBetweenShownPanes() {
    let shown = zip(sourcesController.splitViewItems, sourcePanes)
      .filter { !$0.0.isCollapsed }.map(\.1.pane)
    let pairs =
      showsSeams || !copyDirections.isEmpty ? Array(zip(shown, shown.dropFirst())) : []
    let current = seamSplitView.seams
    if pairs.count != current.count
      || zip(pairs, current).contains(where: { $0.0 !== $1.leftPane || $0.1 !== $1.rightPane })
    {
      let seams = pairs.map(PaneSeam.init)
      for seam in seams {
        seam.theme = shown.first?.theme ?? Theme()
      }
      seamSplitView.seams = seams
    }
    let widths = seamSplitView.seams.map(\.width)
    for seam in seamSplitView.seams {
      seam.showsBands = showsSeams
      seam.copyDirections = copyDirections
      seam.delegate = seamDelegate
    }
    if seamSplitView.seams.map(\.width) != widths {
      seamSplitView.seamsDidChangeWidth()
    }
  }

  /// Learns which buttons the user presses at the seams; the layout does not retain it.
  weak var seamDelegate: (any PaneSeamDelegate)? {
    didSet {
      for seam in seamSplitView.seams {
        seam.delegate = seamDelegate
      }
    }
  }

  /// The seams between the panes side by side in view, from left to right, while they show
  /// seams.
  var seams: [PaneSeam] {
    seamSplitView.seams
  }

  /// The split view of the panes side by side.
  private var seamSplitView: SeamSplitView {
    guard let splitView = sourcesController.splitView as? SeamSplitView else {
      preconditionFailure("The panes side by side lie in a split view with seams")
    }
    return splitView
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
      // The seams lie between the panes as they share the room anew.
      sourcesController.splitView.layoutSubtreeIfNeeded()
      placeSeamsBetweenShownPanes()
      if newValue {
        placeSourceDividers()
      }
    }
  }

  /// Whether the result has the whole window, with the panes above it collapsed.
  ///
  /// - Precondition: The window has a result, if it is to be maximized.
  ///
  /// Giving the panes above back their room puts the divider where it was before.
  var maximizesResult: Bool {
    get { resultPane != nil && splitViewItems.first?.isCollapsed == true }
    set {
      precondition(resultPane != nil || !newValue, "Only a window with a result maximizes it")
      guard newValue != maximizesResult else { return }
      let fraction = currentSourcesFraction
      splitViewItems.first?.isCollapsed = newValue
      if newValue {
        fractionBeforeMaximizing = fraction
      } else if let fractionBeforeMaximizing {
        view.layoutSubtreeIfNeeded()
        splitView.setPosition(
          (splitView.bounds.height * fractionBeforeMaximizing).rounded(), ofDividerAt: 0)
      }
    }
  }

  /// The share of the height that the panes above the result took before the result was
  /// maximized.
  private var fractionBeforeMaximizing: CGFloat?

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
    for seam in seams {
      seam.theme = theme
    }
    resultPane?.theme = theme
    columnPane?.theme = theme
    for headerView in sourceHeaderViews {
      headerView.rootView = SideHeaderView(header: headerView.rootView.header, theme: theme)
    }
    if let columnHeaderView {
      columnHeaderView.rootView = ColumnHeaderView(
        headers: columnHeaderView.rootView.headers, theme: theme)
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
  /// the dividers between them, and the result no narrower than it needs; the single column at
  /// its own least width while it shows.
  var minimumWidth: CGFloat {
    if showsSingleColumn, let columnPane {
      return columnPane.minimumWidth
    }
    // A collapsed pane keeps its divider, which then meets the one beside it.
    let dividers =
      sourcesController.splitView.dividerThickness * CGFloat(max(sourcePanes.count - 1, 0))
    let shown = zip(sourcesController.splitViewItems, sourcePanes).filter { !$0.0.isCollapsed }
    let panes = shown.map(\.1.pane.minimumWidth).reduce(0, +)
    return max(panes + dividers, resultPane?.minimumWidth ?? 0)
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

  /// The share of the height that the panes above the result take in a new window.
  var sourcesFraction = WindowMetrics.sourcesFraction

  /// The share of the height that the panes above the result take now, or `nil` without a
  /// result or while the result has the whole window.
  var currentSourcesFraction: CGFloat? {
    guard resultPane != nil, !maximizesResult, splitView.bounds.height > 0,
      let sources = splitView.arrangedSubviews.first
    else { return nil }
    return sources.frame.height / splitView.bounds.height
  }

  /// Places the dividers as a new window has them: the source panes equally wide, and above
  /// the result their share of the height, ``sourcesFraction``.
  ///
  /// - Precondition: The view is in its window, at the window's size.
  func placeDividers() {
    view.layoutSubtreeIfNeeded()
    if resultPane != nil {
      splitView.setPosition(
        (splitView.bounds.height * sourcesFraction).rounded(), ofDividerAt: 0)
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

  override func splitViewDidResizeSubviews(_ notification: Notification) {
    super.splitViewDidResizeSubviews(notification)
    (splitView as? SeamSplitView)?.placeSeams()
  }
}

/// The split view of the panes side by side, whose dividers are hairlines, or seams that connect
/// the changes of the panes on either side.
///
/// A seam lies over its divider, as wide as ``Theme/seamWidth``, and lets clicks through, so that
/// the divider stays draggable.
@MainActor
private final class SeamSplitView: NSSplitView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    dividerStyle = .thin
    // The seams lie over the dividers; only the panes are arranged.
    arrangesAllSubviews = false
  }

  /// Split views of a window are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// The seams over the dividers, from left to right, or none for dividers of hairlines.
  var seams: [PaneSeam] = [] {
    didSet {
      for seam in oldValue where !seams.contains(seam) {
        seam.removeFromSuperview()
      }
      for seam in seams where seam.superview !== self {
        addSubview(seam)
      }
      seamsDidChangeWidth()
    }
  }

  /// Gives the dividers the thickness of the seams anew, after a seam came, went or changed its
  /// width.
  func seamsDidChangeWidth() {
    // The split view takes the thickness of its dividers anew only when their style changes.
    dividerStyle = .thick
    dividerStyle = .thin
    adjustSubviews()
    // The panes give up the room for the seams in proportion, which may fall between points.
    for index in arrangedSubviews.indices.dropLast()
    where !isSubviewCollapsed(arrangedSubviews[index]) {
      setPosition(arrangedSubviews[index].frame.maxX.rounded(), ofDividerAt: index)
    }
    needsLayout = true
  }

  /// The seams share the room of the dividers: where the pane between two others is
  /// collapsed, its two dividers meet, each half as thick, so that one seam's width lies
  /// between the panes beside it.
  override var dividerThickness: CGFloat {
    let dividerCount = max(arrangedSubviews.count - 1, 1)
    return seams.isEmpty
      ? super.dividerThickness : seams.map(\.width).reduce(0, +) / CGFloat(dividerCount)
  }

  override func drawDivider(in rect: NSRect) {
    guard seams.isEmpty else { return }
    super.drawDivider(in: rect)
  }

  /// A click on a button of a seam goes to the button; the split view keeps the other clicks on
  /// its dividers, so that they stay draggable.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    for seam in seams {
      if let button = seam.hitTest(local) {
        return button
      }
    }
    return super.hitTest(point)
  }

  override func layout() {
    super.layout()
    placeSeams()
  }

  /// Lays each seam over the dividers between its panes, across the full height.
  func placeSeams() {
    for seam in seams {
      guard
        let leftPane = seam.leftPane, let rightPane = seam.rightPane,
        let left = arrangedSubviews.first(where: leftPane.isDescendant(of:)),
        let right = arrangedSubviews.first(where: rightPane.isDescendant(of:))
      else { continue }
      seam.frame = CGRect(
        x: left.frame.maxX, y: bounds.minY, width: right.frame.minX - left.frame.maxX,
        height: bounds.height)
    }
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
