import AppKit
import PaneKit

/// Learns which file the user chose in the list of a window that compares several files.
@MainActor
protocol FileListDelegate: AnyObject {
  /// The user selected the file at `index`.
  func fileList(_ fileList: FileListViewController, didSelectFileAt index: Int)
}

/// The list of the files of a window that compares several, in its sidebar: one row for each
/// file with the sign of what happened to it, its name and its folder; below the rows, while
/// files still come, how many have come.
@MainActor
final class FileListViewController: NSViewController {
  /// Learns which file the user chose; the list does not retain it.
  weak var delegate: (any FileListDelegate)?

  /// The files the list shows.
  private(set) var files: [CollectedFile] = []

  /// The theme whose colors the signs take.
  var theme: Theme {
    didSet { tableView.reloadData() }
  }

  /// The color of the folders, quieter than the names yet readable.
  var folderColor: NSColor {
    didSet { tableView.reloadData() }
  }

  /// The table of the files.
  let tableView = NSTableView()

  /// The line below the rows that tells how many files have come while more are coming.
  let receivingLine = NSStackView()

  private let receivingLabel = NSTextField(labelWithString: "")
  private let receivingIndicator = NSProgressIndicator()
  private var isSelectingFromCode = false

  /// Creates the list with the colors of `theme` and `folderColor`.
  init(theme: Theme, folderColor: NSColor) {
    self.theme = theme
    self.folderColor = folderColor
    super.init(nibName: nil, bundle: nil)
  }

  /// File lists are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let column = NSTableColumn(identifier: Self.column)
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .sourceList
    tableView.rowSizeStyle = .default
    tableView.allowsEmptySelection = false
    tableView.allowsMultipleSelection = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.setAccessibilityLabel(Self.listName)
    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    receivingIndicator.style = .spinning
    receivingIndicator.controlSize = .small
    receivingIndicator.isDisplayedWhenStopped = false
    receivingLabel.font = .preferredFont(forTextStyle: .subheadline)
    receivingLabel.textColor = folderColor
    receivingLabel.lineBreakMode = .byTruncatingTail
    receivingLine.setViews([receivingIndicator, receivingLabel], in: .leading)
    receivingLine.spacing = WindowMetrics.headerSpacing
    receivingLine.edgeInsets = NSEdgeInsets(
      top: 0, left: WindowMetrics.headerInset, bottom: 0, right: WindowMetrics.headerInset)
    receivingLine.translatesAutoresizingMaskIntoConstraints = false
    receivingLine.isHidden = true
    receivingLine.setAccessibilityElement(true)
    receivingLine.setAccessibilityRole(.staticText)

    // The split view gives the sidebar the width its view has when it first shows.
    let container = NSView(
      frame: CGRect(x: 0, y: 0, width: WindowMetrics.sidebarWidth, height: 400))
    container.addSubview(scrollView)
    container.addSubview(receivingLine)
    let receivingHeight = receivingLine.heightAnchor.constraint(
      equalToConstant: WindowMetrics.footerHeight)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: receivingLine.topAnchor),
      receivingLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      receivingLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      receivingLine.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      receivingHeight,
    ])
    self.receivingHeight = receivingHeight
    view = container
  }

  private var receivingHeight: NSLayoutConstraint?

  /// Shows `files`, keeping the selection on the file it is on.
  func show(_ files: [CollectedFile], selecting selection: Int) {
    loadViewIfNeeded()
    self.files = files
    tableView.reloadData()
    select(selection)
  }

  /// Shows that the file at `index` came, below or between the rows there are, keeping the
  /// selection on the file it is on.
  func insert(_ file: CollectedFile, at index: Int, selecting selection: Int) {
    loadViewIfNeeded()
    files.insert(file, at: index)
    isSelectingFromCode = true
    tableView.insertRows(at: IndexSet(integer: index))
    isSelectingFromCode = false
    select(selection)
  }

  /// Selects the row of the file at `index` without telling the delegate, and scrolls it into
  /// view.
  func select(_ index: Int) {
    guard files.indices.contains(index) else { return }
    isSelectingFromCode = true
    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    isSelectingFromCode = false
    tableView.scrollRowToVisible(index)
  }

  /// Shows below the rows that `count` files of `expectedCount`, if known, have come, or hides
  /// the line once no more come.
  func showReceiving(_ count: Int, of expectedCount: Int?, isReceiving: Bool) {
    loadViewIfNeeded()
    receivingLine.isHidden = !isReceiving
    receivingHeight?.constant = isReceiving ? WindowMetrics.footerHeight : 0
    if isReceiving {
      receivingIndicator.startAnimation(nil)
    } else {
      receivingIndicator.stopAnimation(nil)
    }
    receivingLabel.stringValue = Self.receivingText(count, of: expectedCount)
    receivingLine.setAccessibilityLabel(receivingLabel.stringValue)
  }

  /// What the line below the rows says while files come.
  static func receivingText(_ count: Int, of expectedCount: Int?) -> String {
    guard let expectedCount else {
      return String(
        localized: "Receiving Files…", bundle: .module,
        comment: "Sidebar: files still come and it is not known how many.")
    }
    return String(
      localized: "Receiving \(count) of \(expectedCount)…", bundle: .module,
      comment: "Sidebar: how many files of a run have come, such as Receiving 12 of 40….")
  }

  /// What VoiceOver says once every file has come.
  static func receivedText(_ count: Int) -> String {
    String(
      localized: "All \(count) files received", bundle: .module,
      comment: "VoiceOver: every file of a run has come, such as All 40 files received.")
  }

  private static var listName: String {
    String(
      localized: "Files", bundle: .module,
      comment: "VoiceOver: the list of the files in the sidebar of a window that compares several.")
  }

  private static let column = NSUserInterfaceItemIdentifier("file")
}

extension FileListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    files.count
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    let cell =
      tableView.makeView(withIdentifier: FileListCell.identifier, owner: self) as? FileListCell
      ?? FileListCell()
    cell.show(files[row], theme: theme, folderColor: folderColor)
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isSelectingFromCode, tableView.selectedRow >= 0 else { return }
    delegate?.fileList(self, didSelectFileAt: tableView.selectedRow)
  }
}

/// A row of the file list: the sign of what happened to the file, its name, and its folder.
@MainActor
final class FileListCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("FileListCell")

  private let sign = NSImageView()
  private let name = NSTextField(labelWithString: "")
  private let folder = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    identifier = Self.identifier
    sign.setAccessibilityElement(false)
    name.lineBreakMode = .byTruncatingTail
    name.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    name.setContentHuggingPriority(.required, for: .horizontal)
    folder.lineBreakMode = .byTruncatingMiddle
    folder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    folder.setContentHuggingPriority(.defaultLow, for: .horizontal)
    for label in [name, folder] {
      label.font = .preferredFont(forTextStyle: .body)
      label.setAccessibilityElement(false)
    }
    let stack = NSStackView(views: [sign, name, folder])
    stack.spacing = WindowMetrics.footerToggleSpacing + 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    imageView = sign
    textField = name
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      sign.widthAnchor.constraint(equalToConstant: 16),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Shows `file` with the colors of `theme`, its folder in `folderColor`.
  func show(_ file: CollectedFile, theme: Theme, folderColor: NSColor) {
    let path = file.path as NSString
    let folderPath = path.deletingLastPathComponent
    name.stringValue = path.lastPathComponent
    name.textColor = .labelColor
    folder.stringValue = folderPath
    folder.textColor = folderColor
    folder.isHidden = folderPath.isEmpty
    let presentation = file.change.presentation
    sign.image = NSImage(
      systemSymbolName: presentation.symbolName, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(scale: file.change == .modified ? .small : .medium))
    sign.contentTintColor = presentation.color(in: theme)
    toolTip = presentation.toolTip(for: file.path)
    setAccessibilityLabel(
      [path.lastPathComponent, folderPath, presentation.word].filter { !$0.isEmpty }
        .joined(separator: ", "))
  }
}
