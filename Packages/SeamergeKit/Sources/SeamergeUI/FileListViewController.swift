import AppKit
import FolderCompare
import PaneKit

/// Learns which file the user chose in the list of a window that compares several files, and
/// what the user typed to filter it.
@MainActor
protocol FileListDelegate: AnyObject {
  /// The user selected the file at `index` of the files the list was given.
  func fileList(_ fileList: FileListViewController, didSelectFileAt index: Int)

  /// The user changed the text that the list is filtered by.
  func fileList(_ fileList: FileListViewController, didChangeFilter text: String)
}

/// The list of the files of a window that compares several, in its sidebar, grouped by folder.
///
/// The files at the top come first, then each folder as a heading above its files. A row shows
/// the sign of what happened to the file, its name, and a dot while it has copied changes that
/// are not saved.
///
/// The list knows the files by their index among the files it was given, never by their row,
/// so that the selection stays with its file as files come, go or are filtered out.
///
/// Below the rows stands a quiet line while files come or folders are compared, and what a
/// comparison of folders found once it is done; below it the field that filters the list by
/// name or folder.
@MainActor
final class FileListViewController: NSViewController {
  /// Learns which file the user chose; the list does not retain it.
  weak var delegate: (any FileListDelegate)?

  /// The files the list was given, which its groups refer to by index.
  private(set) var files: [CollectedFile] = []

  /// The files the list shows, grouped by folder.
  private(set) var groups = FileGroups(paths: [], folderOrder: .firstFile)

  /// The paths of the files with copied changes that are not saved, which show a dot.
  var changedPaths: Set<String> = [] {
    didSet {
      guard changedPaths != oldValue else { return }
      let changed = IndexSet(
        rows.indices.filter { row in
          guard case .file(let index) = rows[row] else { return false }
          let path = files[index].path
          return changedPaths.contains(path) != oldValue.contains(path)
        })
      tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
    }
  }

  /// The theme whose colors the signs take.
  var theme: Theme {
    didSet { reloadRows() }
  }

  /// The color of the folders, quieter than the names yet readable.
  var folderColor: NSColor {
    didSet {
      reloadRows()
      statusLabel.textColor = folderColor
      emptyLabel.textColor = folderColor
    }
  }

  /// The table of the files: the files at the top, then each folder as a heading over its files.
  let tableView = NSTableView()

  /// The line below the rows that says how many files have come, how far the comparison of
  /// folders is, or what it found.
  let statusLine = NSStackView()

  /// The field that filters the list.
  let filterField = NSSearchField()

  /// What the list says in place of rows when the filter leaves none.
  let emptyLabel = NSTextField(
    labelWithString: String(
      localized: "No Files Match", bundle: .module,
      comment: "Sidebar: no file of the list matches what was typed in the filter field."))

  /// A row of the list.
  private enum Row {
    /// The heading of a folder, relative to the top, above its files.
    case heading(String)

    /// The file at an index of the files the list was given.
    case file(Int)
  }

  /// The rows in order: the files at the top, then each folder followed by its files.
  private var rows: [Row] = []

  /// The row of each file the list shows, by its index among the files.
  private var rowOfFile: [Int?] = []

  private let statusLabel = NSTextField(labelWithString: "")
  private let statusIndicator = NSProgressIndicator()
  private var statusHeight: NSLayoutConstraint?
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
    tableView.floatsGroupRows = true
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.setAccessibilityLabel(Self.listName)
    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .preferredFont(forTextStyle: .body)
    emptyLabel.textColor = folderColor
    emptyLabel.alignment = .center
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    statusIndicator.style = .spinning
    statusIndicator.controlSize = .small
    statusIndicator.isDisplayedWhenStopped = false
    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textColor = folderColor
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    statusLine.setViews([statusIndicator, statusLabel], in: .leading)
    statusLine.spacing = WindowMetrics.headerSpacing
    statusLine.edgeInsets = NSEdgeInsets(
      top: 0, left: WindowMetrics.headerInset, bottom: 0, right: WindowMetrics.headerInset)
    statusLine.translatesAutoresizingMaskIntoConstraints = false
    statusLine.isHidden = true
    statusLine.setAccessibilityElement(true)
    statusLine.setAccessibilityRole(.staticText)

    filterField.placeholderString = Self.filterName
    filterField.setAccessibilityLabel(Self.filterName)
    filterField.sendsSearchStringImmediately = true
    filterField.sendsWholeSearchString = false
    filterField.controlSize = .regular
    filterField.target = self
    filterField.action = #selector(filterDidChange(_:))
    filterField.translatesAutoresizingMaskIntoConstraints = false

    // The split view gives the sidebar the width its view has when it first shows.
    let container = NSView(
      frame: CGRect(x: 0, y: 0, width: WindowMetrics.sidebarWidth, height: 400))
    for view in [scrollView, emptyLabel, statusLine, filterField] as [NSView] {
      container.addSubview(view)
    }
    let statusHeight = statusLine.heightAnchor.constraint(equalToConstant: 0)
    let inset = WindowMetrics.sidebarFilterInset
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: statusLine.topAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
      emptyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
      statusLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      statusLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      statusLine.bottomAnchor.constraint(equalTo: filterField.topAnchor, constant: -inset / 2),
      statusHeight,
      filterField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
      filterField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
      filterField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
    ])
    self.statusHeight = statusHeight
    view = container
  }

  /// Shows `groups` of `files` with the file at `selection` of them selected, or none.
  ///
  /// With `scrolling`, the selected row comes into view. Without it, the list keeps the selected
  /// row where it stands, or else the first file in view, so that files that come above it do
  /// not move what the user looks at.
  func show(
    _ groups: FileGroups, of files: [CollectedFile], selecting selection: Int?, scrolling: Bool
  ) {
    loadViewIfNeeded()
    let anchor = scrolling ? nil : rowInView()
    self.files = files
    self.groups = groups
    reloadRows()
    emptyLabel.isHidden = !(groups.fileCount == 0 && !filterField.stringValue.isEmpty)
    select(selection, scrolling: scrolling)
    // The files may stand at other indices now; their paths stay.
    if let anchor, let index = files.firstIndex(where: { $0.path == anchor.path }),
      let row = rowOfFile[index]
    {
      tableView.scroll(CGPoint(x: 0, y: tableView.rect(ofRow: row).minY - anchor.offset))
    }
  }

  /// Selects the file at `index` of the files the list was given, or none, without telling the
  /// delegate; with `scrolling`, its row comes into view.
  func select(_ index: Int?, scrolling: Bool = true) {
    isSelectingFromCode = true
    defer { isSelectingFromCode = false }
    guard let index, rowOfFile.indices.contains(index), let row = rowOfFile[index] else {
      tableView.deselectAll(nil)
      return
    }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    if scrolling {
      // The table leaves room for the heading of the folder that stays at the top.
      tableView.scrollRowToVisible(row)
    }
  }

  /// Shows `text` below the rows, with the spinning indicator while `isBusy`, or hides the line
  /// for `nil`.
  func showStatus(_ text: String?, isBusy: Bool) {
    loadViewIfNeeded()
    statusLine.isHidden = text == nil
    statusHeight?.constant = text == nil ? 0 : WindowMetrics.footerHeight
    // A stopped indicator keeps its room in the line unless it is hidden.
    statusIndicator.isHidden = !isBusy || text == nil
    if statusIndicator.isHidden {
      statusIndicator.stopAnimation(nil)
    } else {
      statusIndicator.startAnimation(nil)
    }
    statusLabel.stringValue = text ?? ""
    // The sidebar may be too narrow for the whole line.
    statusLine.toolTip = text
    statusLine.setAccessibilityLabel(text)
  }

  /// Makes the rows for the groups, shows them, and notes the row of each file; the delegate
  /// learns nothing of the rows that go meanwhile.
  private func reloadRows() {
    isSelectingFromCode = true
    defer { isSelectingFromCode = false }
    var rows: [Row] = []
    rows.reserveCapacity(groups.fileCount + groups.groups.count)
    var rowOfFile = [Int?](repeating: nil, count: files.count)
    for group in groups.groups {
      if !group.folder.isEmpty {
        rows.append(.heading(group.folder))
      }
      for index in group.members {
        rowOfFile[index] = rows.count
        rows.append(.file(index))
      }
    }
    self.rows = rows
    self.rowOfFile = rowOfFile
    tableView.reloadData()
  }

  /// The file whose row the list keeps in place as it shows other files, and how far the top of
  /// that row stands below the top of what is in view: the selected file if it is in view, else
  /// the first file in view.
  private func rowInView() -> (path: String, offset: CGFloat)? {
    guard let clipView = tableView.enclosingScrollView?.contentView, !rows.isEmpty else {
      return nil
    }
    let visible = clipView.bounds
    let inView = tableView.rows(in: visible)
    let selected = tableView.selectedRow
    let row =
      inView.contains(selected) && selected >= 0
      ? selected
      : (inView.lowerBound..<inView.upperBound).first { row in
        if case .file = rows[row] { true } else { false }
      }
    guard let row, rows.indices.contains(row), case .file(let index) = rows[row] else {
      return nil
    }
    return (files[index].path, tableView.rect(ofRow: row).minY - visible.minY)
  }

  @objc private func filterDidChange(_ sender: NSSearchField) {
    delegate?.fileList(self, didChangeFilter: sender.stringValue)
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

  /// What the line below the rows says while two folders are compared: how many of how many
  /// files, once every entry is paired.
  static func comparingText(_ count: Int, of pairedCount: Int?) -> String {
    guard let pairedCount else {
      return String(
        localized: "Comparing Files…", bundle: .module,
        comment: "Sidebar: the files of two folders are being paired, and it is not known how many."
      )
    }
    return String(
      localized: "Comparing \(count.formatted()) of \(pairedCount.formatted()) Files…",
      bundle: .module,
      comment:
        "Sidebar: how many files of two folders are compared, such as Comparing 1,200 of 5,000 Files…."
    )
  }

  /// What the line below the rows says, and VoiceOver once, when two folders are compared: how
  /// many of their files differ.
  static func differingText(_ count: Int, of fileCount: Int) -> String {
    String(
      localized: "\(count.formatted()) of \(fileCount.formatted()) files differ", bundle: .module,
      comment:
        "Sidebar and VoiceOver: how many files of two compared folders differ, such as 12 of 340 files differ."
    )
  }

  private static var listName: String {
    String(
      localized: "Files", bundle: .module,
      comment: "VoiceOver: the list of the files in the sidebar of a window that compares several.")
  }

  private static var filterName: String {
    String(
      localized: "Filter File Name", bundle: .module,
      comment: "The field at the bottom of the sidebar that narrows the list to matching files.")
  }

  private static let column = NSUserInterfaceItemIdentifier("file")
}

extension FileListViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .heading = rows[row] { true } else { false }
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .file = rows[row] { true } else { false }
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    switch rows[row] {
    case .heading(let folder):
      let cell =
        tableView.makeView(withIdentifier: FolderHeadingCell.identifier, owner: self)
        as? FolderHeadingCell ?? FolderHeadingCell()
      cell.show(folder, color: folderColor)
      return cell
    case .file(let index):
      let file = files[index]
      let cell =
        tableView.makeView(withIdentifier: FileListCell.identifier, owner: self) as? FileListCell
        ?? FileListCell()
      cell.show(file, isChanged: changedPaths.contains(file.path), theme: theme)
      return cell
    }
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard case .heading = rows[row] else { return nil }
    return tableView.makeView(withIdentifier: FolderHeadingRowView.identifier, owner: self)
      as? FolderHeadingRowView ?? FolderHeadingRowView()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let selected = tableView.selectedRow
    guard !isSelectingFromCode, rows.indices.contains(selected),
      case .file(let index) = rows[selected]
    else { return }
    delegate?.fileList(self, didSelectFileAt: index)
  }
}
