import AppKit
import MergeModel

/// The list of recent comparisons in the welcome window, grouped into those opened today and
/// those opened earlier.
///
/// Each line has the symbol of its kind, the names of the files in the order of their roles, the
/// kind and the folder they share, and the time it was opened today or the day it was opened
/// earlier. A double click or Return opens one.
@MainActor
final class RecentComparisonsList: NSObject {
  /// The table of the list.
  let tableView = RecentComparisonsTableView()

  /// The view that holds the table.
  let scrollView = NSScrollView()

  /// The lines of the list from top to bottom: headings and comparisons.
  private(set) var rows: [Row] = []

  /// Called with the comparison that the user opens.
  var onOpen: ((FileComparison) -> Void)?

  /// The color of the kind, the folder and the time.
  var quietTextColor = NSColor.secondaryLabelColor {
    didSet { tableView.reloadData() }
  }

  /// The calendar that tells today from earlier days, and the locale and time zone of the times.
  var calendar = Calendar.autoupdatingCurrent

  /// A line of the list.
  enum Row: Equatable {
    /// The heading of the comparisons opened today or of those opened earlier.
    case heading(String)

    /// A comparison.
    case comparison(RecentComparisons.Entry)
  }

  /// The comparisons of the list, newest first.
  var comparisons: [FileComparison] {
    rows.compactMap { row in
      guard case .comparison(let entry) = row else { return nil }
      return entry.comparison
    }
  }

  override init() {
    super.init()
    let column = NSTableColumn(identifier: Self.column)
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .inset
    tableView.rowHeight = WelcomeMetrics.recentRowHeight
    tableView.usesAutomaticRowHeights = false
    tableView.floatsGroupRows = false
    tableView.backgroundColor = .clear
    tableView.allowsEmptySelection = true
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(openClickedRow(_:))
    tableView.opensSelectedRow = { [weak self] in self?.openSelectedRow() ?? false }
    tableView.setAccessibilityLabel(
      String(
        localized: "Recent Comparisons", bundle: .module,
        comment: "VoiceOver: the list of the comparisons opened last in the welcome window."))
    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
  }

  /// Shows `entries`, those opened on the day of `now` under Today and the others under Earlier.
  func show(_ entries: [RecentComparisons.Entry], now: Date = .now) {
    let calendar = calendar
    let isToday = { (entry: RecentComparisons.Entry) in
      entry.opened.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }
    let today = entries.filter(isToday)
    let earlier = entries.filter { !isToday($0) }
    rows = []
    if !today.isEmpty {
      rows.append(.heading(Self.todayTitle))
      rows += today.map(Row.comparison)
    }
    if !earlier.isEmpty {
      rows.append(.heading(Self.earlierTitle))
      rows += earlier.map(Row.comparison)
    }
    self.now = now
    tableView.reloadData()
  }

  /// What the list says beside a comparison opened at `date`: the time for one opened today, the
  /// day otherwise.
  func dateText(of date: Date?) -> String {
    guard let date else { return "" }
    var style =
      calendar.isDate(date, inSameDayAs: now)
      ? Date.FormatStyle(date: .omitted, time: .shortened)
      : Date.FormatStyle(date: .abbreviated, time: .omitted)
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    style.locale = calendar.locale ?? .autoupdatingCurrent
    return date.formatted(style)
  }

  /// The day that tells today from earlier days.
  private var now = Date.now

  @objc private func openClickedRow(_ sender: Any?) {
    open(row: tableView.clickedRow)
  }

  private func openSelectedRow() -> Bool {
    open(row: tableView.selectedRow)
  }

  @discardableResult
  private func open(row: Int) -> Bool {
    guard rows.indices.contains(row), case .comparison(let entry) = rows[row] else {
      return false
    }
    onOpen?(entry.comparison)
    return true
  }

  /// The heading of the comparisons opened today.
  static var todayTitle: String {
    String(
      localized: "Today", bundle: .module,
      comment: "Welcome window: the heading of the comparisons opened today.")
  }

  /// The heading of the comparisons opened before today.
  static var earlierTitle: String {
    String(
      localized: "Earlier", bundle: .module,
      comment: "Welcome window: the heading of the comparisons opened before today.")
  }

  private static let column = NSUserInterfaceItemIdentifier("comparison")
}

extension RecentComparisonsList: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .heading = rows[row] { true } else { false }
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    if case .heading = rows[row] {
      WelcomeMetrics.recentHeadingHeight
    } else {
      WelcomeMetrics.recentRowHeight
    }
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .comparison = rows[row] { true } else { false }
  }

  func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    switch rows[row] {
    case .heading(let title):
      let label = NSTextField(labelWithString: title)
      label.font = .preferredFont(forTextStyle: .subheadline).bold
      label.textColor = .secondaryLabelColor
      return label
    case .comparison(let entry):
      let cell = RecentComparisonCell()
      cell.show(entry, dateText: dateText(of: entry.opened), quietColor: quietTextColor)
      return cell
    }
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

/// A line of the recent comparisons: the symbol of its kind, the names in bold, the kind and the
/// folder below them, and the time or the day at the trailing edge.
final class RecentComparisonCell: NSTableCellView {
  /// The symbol of the kind: two files, a merge or two folders.
  let symbolView = NSImageView()

  /// The names of the files in the order of their roles.
  let namesLabel = NSTextField(labelWithString: "")

  /// The kind of the comparison.
  let kindLabel = NSTextField(labelWithString: "")

  /// The folder the files share, shortened at its start where it is too long.
  let folderLabel = NSTextField(labelWithString: "")

  /// The time or the day it was opened.
  let dateLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    symbolView.symbolConfiguration = .init(pointSize: 15, weight: .regular)
    namesLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    namesLabel.lineBreakMode = .byTruncatingMiddle
    for label in [kindLabel, folderLabel] {
      label.font = .preferredFont(forTextStyle: .subheadline)
    }
    folderLabel.lineBreakMode = .byTruncatingHead
    kindLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    kindLabel.setContentHuggingPriority(.required, for: .horizontal)
    dateLabel.font = .monospacedDigitSystemFont(
      ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
    dateLabel.alignment = .right
    for label in [namesLabel, folderLabel] {
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    dateLabel.setContentHuggingPriority(.required, for: .horizontal)
    let details = NSStackView(views: [kindLabel, folderLabel])
    details.spacing = WelcomeMetrics.recentColumnSpacing / 2
    let text = NSStackView(views: [namesLabel, details])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 1
    for view in [symbolView, text, dateLabel] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.setAccessibilityElement(false)
      addSubview(view)
    }
    textField = namesLabel
    imageView = symbolView
    let spacing = WelcomeMetrics.recentColumnSpacing
    NSLayoutConstraint.activate([
      symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: spacing / 2),
      symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbolView.widthAnchor.constraint(equalToConstant: WelcomeMetrics.recentSymbolWidth),
      text.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: spacing),
      text.centerYAnchor.constraint(equalTo: centerYAnchor),
      dateLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: text.trailingAnchor, constant: spacing),
      dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -spacing / 2),
      dateLabel.firstBaselineAnchor.constraint(equalTo: namesLabel.firstBaselineAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// On the accent color of a selected line, everything turns to the text color of a selection,
  /// as text in the system's colors does by itself; quiet text would stay dark on the accent.
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet { applyColors() }
  }

  /// The color of the kind, the folder and the time on the plain background of the list.
  private var quietColor = NSColor.secondaryLabelColor

  /// Shows `entry`, opened at the time or on the day `dateText`, with quiet text in `quietColor`.
  func show(_ entry: RecentComparisons.Entry, dateText: String, quietColor: NSColor) {
    let comparison = entry.comparison
    symbolView.image = NSImage(
      systemSymbolName: comparison.symbolName, accessibilityDescription: nil)
    namesLabel.stringValue = comparison.title
    kindLabel.stringValue = String(
      localized: "\(comparison.kindName) ·", bundle: .module,
      comment: "Welcome window: the kind of a recent comparison before its folder, such as Merge ·."
    )
    folderLabel.stringValue = comparison.folder
    dateLabel.stringValue = dateText
    self.quietColor = quietColor
    applyColors()
    setAccessibilityLabel(comparison.accessibilityTitle)
    setAccessibilityValue(
      dateText.isEmpty ? comparison.folder : "\(comparison.folder), \(dateText)")
  }

  private func applyColors() {
    let isEmphasized = backgroundStyle == .emphasized
    let selected = NSColor.alternateSelectedControlTextColor
    namesLabel.textColor = isEmphasized ? selected : .labelColor
    symbolView.contentTintColor = isEmphasized ? selected : .secondaryLabelColor
    for label in [kindLabel, folderLabel, dateLabel] {
      label.textColor = isEmphasized ? selected : quietColor
    }
  }
}

extension FileComparison {
  /// The name of the symbol of the kind of the comparison, as its button in the welcome window
  /// shows it.
  var symbolName: String {
    if comparesFolders {
      WelcomeSidebar.foldersSymbol
    } else if kind == .merge {
      WelcomeSidebar.mergeSymbol
    } else {
      WelcomeSidebar.compareSymbol
    }
  }

  /// The kind of the comparison as a line of the recent comparisons names it.
  var kindName: String {
    if comparesFolders {
      String(
        localized: "Folder Comparison", bundle: .module,
        comment: "Welcome window: the kind of a recent comparison of two folders.")
    } else if kind == .merge {
      String(
        localized: "Merge", bundle: .module,
        comment: "Welcome window: the kind of a recent merge of three files.")
    } else {
      String(
        localized: "Comparison", bundle: .module,
        comment: "Welcome window: the kind of a recent comparison of two files.")
    }
  }
}

extension NSFont {
  /// The font in bold, or the font itself if it has no bold.
  fileprivate var bold: NSFont {
    NSFont(descriptor: fontDescriptor.withSymbolicTraits(.bold), size: pointSize) ?? self
  }
}
