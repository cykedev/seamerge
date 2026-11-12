import AppKit

/// The list of recent comparisons in the window Compare Files.
///
/// Each line has the names of the files in the order of their roles and the folder they share. A
/// double click or Return opens one.
@MainActor
final class RecentComparisonsList: NSObject {
  /// The table of the list.
  let tableView = RecentComparisonsTableView()

  /// The view that holds the table, at the height of the most lines the list shows.
  let scrollView = NSScrollView()

  /// The comparisons in the list, newest first.
  private(set) var comparisons: [FileComparison] = []

  /// Called with the comparison that the user opens.
  var onOpen: ((FileComparison) -> Void)?

  /// The color of the folders.
  var quietTextColor = NSColor.labelColor {
    didSet { tableView.reloadData() }
  }

  private var heightConstraint: NSLayoutConstraint?

  override init() {
    super.init()
    let column = NSTableColumn(identifier: Self.column)
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .plain
    tableView.intercellSpacing = CGSize(width: 0, height: tableView.intercellSpacing.height)
    tableView.rowHeight = CompareFilesMetrics.recentRowHeight
    tableView.backgroundColor = .clear
    tableView.allowsEmptySelection = true
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(openClickedRow(_:))
    tableView.opensSelectedRow = { [weak self] in self?.openSelectedRow() ?? false }
    tableView.setAccessibilityLabel(
      String(
        localized: "Recent", bundle: .module,
        comment: "Compare Files: the heading of the comparisons opened last."))
    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
    heightConstraint?.isActive = true
  }

  /// Shows the first comparisons of `comparisons`, as many as the list has lines.
  ///
  /// With `fitting`, the list takes the height of its lines; otherwise it keeps its height, so
  /// that nothing moves while the window is open.
  func show(_ comparisons: [FileComparison], fitting: Bool) {
    self.comparisons = Array(comparisons.prefix(CompareFilesMetrics.recentRowCount))
    tableView.reloadData()
    if fitting {
      let rowHeight = CompareFilesMetrics.recentRowHeight + tableView.intercellSpacing.height
      heightConstraint?.constant = CGFloat(self.comparisons.count) * rowHeight
    }
  }

  @objc private func openClickedRow(_ sender: Any?) {
    guard comparisons.indices.contains(tableView.clickedRow) else { return }
    onOpen?(comparisons[tableView.clickedRow])
  }

  private func openSelectedRow() -> Bool {
    guard comparisons.indices.contains(tableView.selectedRow) else { return false }
    onOpen?(comparisons[tableView.selectedRow])
    return true
  }

  private static let column = NSUserInterfaceItemIdentifier("comparison")
}

extension RecentComparisonsList: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    comparisons.count
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    let cell = RecentComparisonCell()
    cell.show(comparisons[row], folderColor: quietTextColor)
    return cell
  }
}

/// The table of recent comparisons, which opens the selected one with Return while it has the
/// focus, before the default button of the window takes the key.
final class RecentComparisonsTableView: NSTableView {
  /// Opens the selected comparison and tells whether there was one.
  var opensSelectedRow: (() -> Bool)?

  /// Opens the selected comparison if `event` is Return or Enter without modifier keys.
  func handleReturn(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    guard event.type == .keyDown, modifiers.isEmpty,
      ["\r", "\u{3}"].contains(event.charactersIgnoringModifiers)
    else { return false }
    return opensSelectedRow?() ?? false
  }
}

/// A line of the recent comparisons.
private final class RecentComparisonCell: NSTableCellView {
  private let namesLabel = NSTextField(labelWithString: "")
  private let folderLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    namesLabel.lineBreakMode = .byTruncatingMiddle
    namesLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    folderLabel.lineBreakMode = .byTruncatingHead
    folderLabel.alignment = .right
    folderLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
    folderLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    for label in [namesLabel, folderLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      label.setAccessibilityElement(false)
      addSubview(label)
    }
    textField = namesLabel
    NSLayoutConstraint.activate([
      namesLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      namesLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      folderLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: namesLabel.trailingAnchor, constant: CompareFilesMetrics.fieldInset),
      folderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      folderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func show(_ comparison: FileComparison, folderColor: NSColor) {
    folderLabel.textColor = folderColor
    namesLabel.stringValue = comparison.title
    folderLabel.stringValue = comparison.folder
    setAccessibilityLabel(comparison.accessibilityTitle)
    setAccessibilityValue(comparison.folder)
  }
}
