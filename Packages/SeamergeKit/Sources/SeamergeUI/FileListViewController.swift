import AppKit
import FolderCompare
import PaneKit

/// Learns which file the user chose in the list of a window that compares several files, and
/// what the user typed to filter it.
@MainActor
protocol FileListDelegate: AnyObject {
  /// The user selected the file in row `row` of the list.
  func fileList(_ fileList: FileListViewController, didSelectRow row: Int)

  /// The user changed the text that the list is filtered by.
  func fileList(_ fileList: FileListViewController, didChangeFilter text: String)
}

/// The list of the files of a window that compares several, in its sidebar: one row for each
/// file with the sign of what happened to it, its name and its folder, and a dot while it has
/// copied changes that are not saved.
///
/// Below the rows stands a quiet line while files come or folders are compared, and what a
/// comparison of folders found once it is done; below it the field that filters the list by
/// name or folder.
@MainActor
final class FileListViewController: NSViewController {
  /// Learns which file the user chose; the list does not retain it.
  weak var delegate: (any FileListDelegate)?

  /// The files the list shows.
  private(set) var files: [CollectedFile] = []

  /// The paths of the files with copied changes that are not saved, which show a dot.
  var changedPaths: Set<String> = [] {
    didSet {
      guard changedPaths != oldValue else { return }
      let rows = IndexSet(
        files.indices.filter {
          changedPaths.contains(files[$0].path) != oldValue.contains(files[$0].path)
        })
      tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
    }
  }

  /// The theme whose colors the signs take.
  var theme: Theme {
    didSet { tableView.reloadData() }
  }

  /// The color of the folders, quieter than the names yet readable.
  var folderColor: NSColor {
    didSet {
      tableView.reloadData()
      statusLabel.textColor = folderColor
      emptyLabel.textColor = folderColor
    }
  }

  /// The table of the files.
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

  /// Shows `files` with the row `selection` selected, or none; with `scrolling`, the selected
  /// row comes into view.
  func show(_ files: [CollectedFile], selecting selection: Int?, scrolling: Bool) {
    loadViewIfNeeded()
    self.files = files
    isSelectingFromCode = true
    tableView.reloadData()
    isSelectingFromCode = false
    emptyLabel.isHidden = !(files.isEmpty && !filterField.stringValue.isEmpty)
    select(selection, scrolling: scrolling)
  }

  /// Selects row `row`, or none, without telling the delegate; with `scrolling`, the row comes
  /// into view.
  func select(_ row: Int?, scrolling: Bool = true) {
    isSelectingFromCode = true
    defer { isSelectingFromCode = false }
    guard let row, files.indices.contains(row) else {
      tableView.deselectAll(nil)
      return
    }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    if scrolling {
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
    files.count
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    let cell =
      tableView.makeView(withIdentifier: FileListCell.identifier, owner: self) as? FileListCell
      ?? FileListCell()
    cell.show(
      files[row], isChanged: changedPaths.contains(files[row].path), theme: theme,
      folderColor: folderColor)
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isSelectingFromCode, tableView.selectedRow >= 0 else { return }
    delegate?.fileList(self, didSelectRow: tableView.selectedRow)
  }
}

/// A row of the file list: the sign of what happened to the file, its name, its folder, and a
/// dot while it has copied changes that are not saved.
@MainActor
final class FileListCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("FileListCell")

  private let sign = NSImageView()
  private let name = NSTextField(labelWithString: "")
  private let folder = NSTextField(labelWithString: "")
  private let changedDot = NSImageView()

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
    // The dot of a document with unsaved changes, as in the close button: a template image that
    // takes the color of the text, also in a selected row.
    changedDot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: WindowMetrics.changedFileDotSize, weight: .regular))
    changedDot.setAccessibilityElement(false)
    changedDot.setContentCompressionResistancePriority(.required, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    let stack = NSStackView(views: [sign, name, folder, spacer, changedDot])
    stack.spacing = WindowMetrics.footerToggleSpacing + 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    imageView = sign
    textField = name
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      stack.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -WindowMetrics.changedFileDotInset),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      sign.widthAnchor.constraint(equalToConstant: 16),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Shows `file` with the sign of what happened to it in the colors of `theme`, its folder in
  /// `folderColor`, and a dot if it `isChanged`, which VoiceOver reads as Edited.
  func show(_ file: CollectedFile, isChanged: Bool, theme: Theme, folderColor: NSColor) {
    let path = file.path as NSString
    let folderPath = path.deletingLastPathComponent
    name.stringValue = path.lastPathComponent
    name.textColor = .labelColor
    folder.stringValue = folderPath
    folder.textColor = folderColor
    folder.isHidden = folderPath.isEmpty
    changedDot.isHidden = !isChanged
    let presentation = file.change.presentation
    sign.image = NSImage(
      systemSymbolName: presentation.symbolName, accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(scale: presentation.isSmall ? .small : .medium))
    sign.contentTintColor = presentation.color(in: theme)
    toolTip = presentation.toolTip(for: file.path)
    setAccessibilityLabel(
      [
        path.lastPathComponent, folderPath, presentation.word,
        isChanged ? SideHeader.editedText : "",
      ]
      .filter { !$0.isEmpty }.joined(separator: ", "))
  }
}
