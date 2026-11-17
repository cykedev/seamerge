import AppKit
import MergeModel

/// What the welcome window asks of the app: to open a session.
@MainActor
public protocol WelcomeWindowControllerDelegate: AnyObject {
  /// Opens a session for the files of `comparison`, in their roles, and returns once its window
  /// shows.
  ///
  /// - Throws: Why the files cannot be opened; the window shows it in a sheet with the files.
  func welcomeWindowController(
    _ controller: WelcomeWindowController, open comparison: FileComparison) async throws
}

/// The welcome window: the start window of the app, from which a comparison or a merge begins.
///
/// On the left, on the deep blue of the website, are the icon, name and version of the app, the
/// buttons Compare Files…, Compare Folders… and Merge Files…, and the place that invites files.
/// On the right are the comparisons opened last and the line about Git. The buttons show the
/// sheets with the fields for the files; two files or folders dropped on the window open at
/// once, three fill the sheet Merge Files. Once a session window shows, the window closes and
/// lists the files among the comparisons opened last; if they cannot be opened, a sheet says why
/// and keeps them.
@MainActor
public final class WelcomeWindowController: NSWindowController {
  /// Opens the sessions of the window; the window does not retain it, and opens nothing
  /// without one.
  public weak var delegate: (any WelcomeWindowControllerDelegate)?

  /// The column with the name of the app, its buttons and the place to drop files.
  let sidebar: WelcomeSidebar

  /// The comparisons opened last.
  let recentList = RecentComparisonsList()

  /// The comparisons opened last, which the window lists and adds to.
  let recentComparisons: RecentComparisons

  /// The sheet Compare Files or Merge Files while it is shown.
  var filesSheet: CompareFilesWindowController?

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet { applyColors() }
  }

  /// The open panel and the sheet of a failure.
  let panels: any CompareFilesPanels

  /// Tells VoiceOver what changed.
  let announce: (String) -> Void

  /// Whether a comparison is being opened from the list or from a drop.
  private(set) var isOpening = false

  /// Reads and writes the settings of Git and Tower, or `nil` for a window without the line
  /// about Git.
  let integrationStore: (any IntegrationStore)?

  /// What the settings of Git and Tower said when they were last read, `nil` until then.
  var integrationStatus: IntegrationStatus?

  /// The line at the bottom: whether Git opens Seamerge.
  let gitStatusLabel = NSTextField(labelWithString: "")

  /// The button next to the line, which shows the sheet Set Up Git Integration.
  let gitSetUpButton: NSButton

  /// The sheet Set Up Git Integration while it is shown.
  var integrationSheet: GitIntegrationSheet?

  /// A sheet of files waiting for another sheet of the window to end.
  var pendingFilesSheet: (() -> Void)?

  /// The words in place of the list while it is empty, which name the next step.
  let emptyListView: NSStackView

  /// Creates the window, which lists the comparisons of `recentComparisons`, says at the bottom
  /// what the settings in `integrationStore` say about Git, and draws with the accessibility
  /// settings of the system.
  public convenience init(
    recentComparisons: RecentComparisons, integrationStore: SystemIntegrationStore
  ) {
    let window = WelcomeWindow()
    self.init(
      recentComparisons: recentComparisons, displayOptions: .current(in: .shared),
      panels: SystemPanels(), window: window, integrationStore: integrationStore,
      icon: NSApplication.shared.applicationIconImage,
      version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) { text in
      NSAccessibility.post(
        element: window, notification: .announcementRequested,
        userInfo: [
          .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  /// Creates the window, which draws with `displayOptions`, asks with `panels`, reads and writes
  /// the settings of Git with `integrationStore`, shows `icon` and `version` and tells VoiceOver
  /// what changed through `announce`.
  init(
    recentComparisons: RecentComparisons, displayOptions: DisplayOptions,
    panels: any CompareFilesPanels, window: WelcomeWindow,
    integrationStore: (any IntegrationStore)? = nil, icon: NSImage, version: String?,
    announce: @escaping (String) -> Void
  ) {
    self.recentComparisons = recentComparisons
    self.integrationStore = integrationStore
    self.displayOptions = displayOptions
    self.panels = panels
    self.announce = announce
    sidebar = WelcomeSidebar(icon: icon, version: version, colors: WelcomeColors(displayOptions))
    gitSetUpButton = NSButton(
      title: String(
        localized: "Set Up Git Integration…", bundle: .module,
        comment: "Welcome window: the button next to the line about Git."),
      target: nil, action: nil)
    emptyListView = Self.makeEmptyListView()
    super.init(window: window)

    window.delegate = self
    window.contentView = makeContent()
    sidebar.compareFilesButton.target = self
    sidebar.compareFilesButton.action = #selector(showCompareFiles(_:))
    sidebar.compareFoldersButton.target = self
    sidebar.compareFoldersButton.action = #selector(showCompareFolders(_:))
    sidebar.mergeFilesButton.target = self
    sidebar.mergeFilesButton.action = #selector(showMergeFiles(_:))
    gitSetUpButton.target = self
    gitSetUpButton.action = #selector(showGitIntegration(_:))
    gitSetUpButton.isHidden = true
    recentList.onOpen = { [weak self] comparison in self?.open(comparison) }
    NotificationCenter.default.addObserver(
      self, selector: #selector(recentComparisonsDidChange(_:)),
      name: RecentComparisons.didChangeNotification, object: recentComparisons)
    applyColors()
    showRecentComparisons()
    window.setContentSize(WelcomeMetrics.contentSize)
    window.center()
  }

  /// Welcome windows are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  private func makeContent() -> NSView {
    let content = FileDropView()
    content.delegate = self
    let list = recentList.scrollView
    for view in [sidebar, list, emptyListView] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    let margin = WelcomeMetrics.listMargin
    NSLayoutConstraint.activate([
      sidebar.topAnchor.constraint(equalTo: content.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: WelcomeMetrics.sidebarWidth),
      list.topAnchor.constraint(
        equalTo: content.topAnchor, constant: WelcomeMetrics.titleBarHeight),
      list.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: margin / 2),
      list.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin / 2),
      list.bottomAnchor.constraint(
        equalTo: content.bottomAnchor, constant: -WelcomeMetrics.gitStatusHeight),
      emptyListView.centerXAnchor.constraint(equalTo: list.centerXAnchor),
      emptyListView.centerYAnchor.constraint(equalTo: list.centerYAnchor),
      emptyListView.widthAnchor.constraint(lessThanOrEqualTo: list.widthAnchor, constant: -margin),
    ])
    addGitStatusRow(to: content, after: sidebar)
    return content
  }

  /// The words of the empty list: that there are no recent comparisons, and how to start one.
  private static func makeEmptyListView() -> NSStackView {
    let title = NSTextField(
      labelWithString: String(
        localized: "No Recent Comparisons", bundle: .module,
        comment: "Welcome window: the list of recent comparisons while it is empty."))
    title.font = .preferredFont(forTextStyle: .title3)
    let hint = NSTextField(
      wrappingLabelWithString: String(
        localized: "Choose Compare Files… or drop two files on this window.", bundle: .module,
        comment: "Welcome window: the next step below No Recent Comparisons."))
    hint.alignment = .center
    let stack = NSStackView(views: [title, hint])
    stack.orientation = .vertical
    stack.spacing = WelcomeMetrics.emptyListSpacing
    return stack
  }

  /// Shows the window in front with the recent comparisons as of now, and reads again what Git
  /// says.
  public override func showWindow(_ sender: Any?) {
    showRecentComparisons()
    super.showWindow(sender)
    if integrationSheet == nil {
      Task { await readIntegrationStatus() }
    }
  }

  /// Opens `comparison` from the list or from a drop; once its window shows, remembers it and
  /// closes, and otherwise shows it in its sheet with why it cannot be opened.
  func open(_ comparison: FileComparison) {
    guard !isOpening, let delegate else { return }
    isOpening = true
    Task {
      defer { isOpening = false }
      do {
        try await delegate.welcomeWindowController(self, open: comparison)
      } catch {
        showFailure(error, opening: comparison)
        return
      }
      didOpen(comparison)
    }
  }

  /// Remembers `comparison`, whose window shows, and closes the window with its sheet.
  func didOpen(_ comparison: FileComparison) {
    recentComparisons.add(comparison)
    if let sheetWindow = filesSheet?.window {
      window?.endSheet(sheetWindow)
    }
    close()
  }

  private func applyColors() {
    let colors = CompareFilesColors(displayOptions)
    sidebar.colors = WelcomeColors(displayOptions)
    gitStatusLabel.textColor = colors.quietText
    recentList.quietTextColor = colors.quietText
    for case let label as NSTextField in emptyListView.arrangedSubviews {
      label.textColor = colors.quietText
    }
    filesSheet?.displayOptions = displayOptions
  }

  /// Lists the recent comparisons, or says how to start one while there are none.
  private func showRecentComparisons() {
    let entries = recentComparisons.entries
    recentList.show(entries)
    recentList.scrollView.isHidden = entries.isEmpty
    emptyListView.isHidden = !entries.isEmpty
  }

  @objc private func recentComparisonsDidChange(_ notification: Notification) {
    showRecentComparisons()
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    displayOptions = .current(in: .shared)
  }
}

extension WelcomeWindowController: NSWindowDelegate {
  /// Shows the sheet of files that waited for another sheet, once that has ended.
  public func windowDidEndSheet(_ notification: Notification) {
    guard let pending = pendingFilesSheet else { return }
    pendingFilesSheet = nil
    // The window lets go of the sheet only after it has told its delegate.
    Task { pending() }
  }
}

extension WelcomeWindowController: NSUserInterfaceValidations {
  /// Set Up Git Integration… needs Git and no sheet on the window; the other commands of the
  /// window always work.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(showGitIntegration(_:)):
      canSetUpGitIntegration && integrationSheet == nil && window?.attachedSheet == nil
    default: true
    }
  }
}
