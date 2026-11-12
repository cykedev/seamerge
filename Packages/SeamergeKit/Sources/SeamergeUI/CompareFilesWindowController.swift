import AppKit

/// What the window Compare Files asks of the app: to open a session.
@MainActor
public protocol CompareFilesWindowControllerDelegate: AnyObject {
  /// Opens a session for the files of `comparison`, in their roles, and returns once its window
  /// shows.
  ///
  /// - Throws: Why the files cannot be opened; the window shows it in a sheet and keeps them.
  func compareFilesWindowController(
    _ controller: CompareFilesWindowController, open comparison: FileComparison) async throws
}

/// The window Compare Files: the start window of the app and the window of File > Compare Files….
///
/// It has three fields in the order of the panes, Left, Base and Right. Two outer files are
/// compared, three are merged; the button below says which and opens them in exactly the roles
/// shown. Once the session window shows, the window closes and lists the files among the
/// comparisons opened last; if they cannot be opened, it says why and keeps them. The window
/// never opens anything by itself.
@MainActor
public final class CompareFilesWindowController: NSWindowController {
  /// Opens the sessions of the window; the window does not retain it, and opens nothing
  /// without one.
  public weak var delegate: (any CompareFilesWindowControllerDelegate)? {
    didSet { selectionDidChange() }
  }

  /// The files in the fields.
  var selection = FileSelection()

  /// The fields, by their place.
  let fields: [FileSlot: FileField]

  /// The default button, Compare or Merge, which opens the files in the fields.
  let openButton: NSButton

  /// The comparisons opened last.
  let recentList = RecentComparisonsList()

  /// The words below the fields, which say their roles.
  let captions: [FileSlot: NSTextField]

  /// Whether the files of the fields are being opened.
  private(set) var isOpening = false

  /// The accessibility settings the window draws with.
  var displayOptions: DisplayOptions {
    didSet { applyColors() }
  }

  /// The fields that a drag going on now would fill, and the roles they would take.
  var dropTargets: [FileSlot: String] = [:] {
    didSet { showDropTargets() }
  }

  /// The comparisons opened last, which the window lists and adds to.
  let recentComparisons: RecentComparisons

  /// The open panel and the sheet of a failure.
  let panels: any CompareFilesPanels

  /// Tells VoiceOver what changed.
  let announce: (String) -> Void
  private let heading: NSTextField
  private let recentSection: NSStackView

  /// Creates the window, which lists the comparisons of `recentComparisons` and draws with the
  /// accessibility settings of the system.
  public convenience init(recentComparisons: RecentComparisons) {
    let window = CompareFilesWindow()
    self.init(
      recentComparisons: recentComparisons, displayOptions: .current(in: .shared),
      panels: SystemPanels(), window: window
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

  /// Creates the window, which draws with `displayOptions`, asks with `panels` and tells
  /// VoiceOver what changed through `announce`.
  init(
    recentComparisons: RecentComparisons, displayOptions: DisplayOptions,
    panels: any CompareFilesPanels, window: CompareFilesWindow,
    announce: @escaping (String) -> Void
  ) {
    self.recentComparisons = recentComparisons
    self.displayOptions = displayOptions
    self.panels = panels
    self.announce = announce
    let colors = CompareFilesColors(displayOptions)
    var fields: [FileSlot: FileField] = [:]
    var captions: [FileSlot: NSTextField] = [:]
    for slot in FileSlot.allCases {
      fields[slot] = FileField(slot: slot, colors: colors)
      let caption = NSTextField(labelWithString: "")
      caption.alignment = .center
      caption.setAccessibilityElement(false)
      captions[slot] = caption
    }
    self.fields = fields
    self.captions = captions
    openButton = NSButton(title: "", target: nil, action: nil)
    heading = NSTextField(
      labelWithString: String(
        localized: "Recent", bundle: .module,
        comment: "Compare Files: the heading of the comparisons opened last."))
    heading.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    heading.setAccessibilityElement(false)
    recentSection = NSStackView(views: [heading, recentList.scrollView])
    super.init(window: window)

    window.delegate = self
    window.contentView = makeContent()
    for field in fields.values {
      field.delegate = self
    }
    openButton.target = self
    openButton.action = #selector(openComparison(_:))
    openButton.keyEquivalent = "\r"
    recentList.onOpen = { [weak self] comparison in self?.open(comparison) }
    NotificationCenter.default.addObserver(
      self, selector: #selector(recentComparisonsDidChange(_:)),
      name: RecentComparisons.didChangeNotification, object: recentComparisons)
    applyColors()
    showRecentComparisons(fitting: true)
    selectionDidChange()
    window.center()
  }

  /// Windows of Compare Files are never archived.
  public required init?(coder: NSCoder) {
    nil
  }

  private func makeContent() -> NSView {
    let columns = FileSlot.allCases.compactMap { slot -> NSView? in
      guard let field = fields[slot], let caption = captions[slot] else { return nil }
      let column = NSStackView(views: [field, caption])
      column.orientation = .vertical
      column.spacing = CompareFilesMetrics.captionSpacing
      caption.widthAnchor.constraint(equalTo: field.widthAnchor).isActive = true
      return column
    }
    let fieldsRow = NSStackView(views: columns)
    fieldsRow.spacing = CompareFilesMetrics.fieldSpacing
    fieldsRow.alignment = .top
    let buttonRow = NSStackView(views: [NSView(), openButton])
    buttonRow.distribution = .fill
    recentSection.orientation = .vertical
    recentSection.alignment = .leading
    recentSection.spacing = CompareFilesMetrics.headingSpacing
    recentList.scrollView.widthAnchor.constraint(equalTo: recentSection.widthAnchor)
      .isActive = true

    let stack = NSStackView(views: [fieldsRow, buttonRow, recentSection])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = CompareFilesMetrics.sectionSpacing
    let margin = CompareFilesMetrics.margin
    stack.edgeInsets = NSEdgeInsets(
      top: margin, left: margin, bottom: margin + CompareFilesMetrics.gitStatusHeight,
      right: margin)
    stack.translatesAutoresizingMaskIntoConstraints = false
    for row in [buttonRow, recentSection] {
      row.widthAnchor.constraint(equalTo: fieldsRow.widthAnchor).isActive = true
    }

    let content = FileDropView()
    content.delegate = self
    content.addSubview(stack)
    // The window takes the height of its content when it appears and keeps it while it is open;
    // a list that empties then leaves room below rather than moving the window.
    let fittingBottom = stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
    fittingBottom.priority = .defaultLow
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor), fittingBottom,
    ])
    return content
  }

  /// Shows the window in front, at the height of its content, with the focus on the first empty
  /// field.
  public override func showWindow(_ sender: Any?) {
    if window?.isVisible != true {
      showRecentComparisons(fitting: true)
    }
    selectionDidChange()
    super.showWindow(sender)
    focusFirstEmptyField()
  }

  /// Puts `urls` in the fields as if they were dropped on the window and tells whether the
  /// window took them; it takes no folders and no more than three files.
  @discardableResult
  public func fill(with urls: [URL]) -> Bool {
    guard
      urls.allSatisfy({ !$0.hasDirectoryPath }),
      let places = selection.places(for: urls, droppedOn: nil)
    else { return false }
    fill(places)
    return true
  }

  /// Swaps the files of the outer fields.
  @objc public func swapSides(_ sender: Any?) {
    selection.swap(.left, .right)
    selectionDidChange()
    announceSwap(of: .left, and: .right)
  }

  /// Opens the files of the fields in their roles and closes the window.
  @objc func openComparison(_ sender: Any?) {
    guard let comparison = selection.comparison else { return }
    open(comparison)
  }

  /// Opens `comparison`; once its window shows, remembers it and closes, and otherwise says why
  /// in a sheet and keeps the files.
  func open(_ comparison: FileComparison) {
    guard !isOpening, let delegate, let window else { return }
    isOpening = true
    selectionDidChange()
    Task {
      defer {
        isOpening = false
        selectionDidChange()
      }
      do {
        try await delegate.compareFilesWindowController(self, open: comparison)
      } catch {
        await panels.showFailure(error, in: window)
        return
      }
      recentComparisons.add(comparison)
      selection = FileSelection()
      close()
    }
  }

  func fill(_ places: [FileSlot: URL]) {
    selection.fill(places)
    selectionDidChange()
    let hasBase = selection.hasBase
    announce(
      FileSlot.allCases.compactMap { slot in
        places[slot].map { url in
          String(
            localized: "\(url.lastPathComponent) added as \(slot.title(hasBase: hasBase))",
            bundle: .module,
            comment: "VoiceOver: a file was put in a field, such as LoginView.swift added as Base.")
        }
      }.joined(separator: ". "))
  }

  func clear(_ slot: FileSlot) {
    guard let url = selection[slot] else { return }
    let role = slot.title(hasBase: selection.hasBase)
    selection[slot] = nil
    selectionDidChange()
    announce(
      String(
        localized: "\(url.lastPathComponent) removed from \(role)", bundle: .module,
        comment: "VoiceOver: a field was emptied, such as LoginView.swift removed from Left."))
  }

  func announceSwap(of first: FileSlot, and second: FileSlot) {
    let hasBase = selection.hasBase
    announce(
      String(
        localized: "Swapped \(first.title(hasBase: hasBase)) and \(second.title(hasBase: hasBase))",
        bundle: .module, comment: "VoiceOver: two fields swapped their files."))
  }

  /// Shows the files of the fields, the roles they have now and what the button would open.
  func selectionDidChange() {
    let hasBase = selection.hasBase
    for slot in FileSlot.allCases {
      fields[slot]?.update(url: selection[slot], hasBase: hasBase)
    }
    showDropTargets()
    openButton.title =
      hasBase
      ? String(
        localized: "Merge", bundle: .module,
        comment: "Compare Files: the default button with three files.")
      : String(
        localized: "Compare", bundle: .module,
        comment: "Compare Files: the default button with two files.")
    openButton.isEnabled = !isOpening && selection.comparison != nil && delegate != nil
  }

  /// Says below each field its role, or the role a drop would give it while one would fill it,
  /// next to the border of the field.
  private func showDropTargets() {
    let hasBase = selection.hasBase
    for slot in FileSlot.allCases {
      fields[slot]?.isDropTarget = dropTargets[slot] != nil
      captions[slot]?.stringValue = dropTargets[slot] ?? slot.title(hasBase: hasBase)
    }
  }

  private func applyColors() {
    let colors = CompareFilesColors(displayOptions)
    for field in fields.values {
      field.colors = colors
    }
    for caption in captions.values {
      caption.textColor = colors.quietText
    }
    heading.textColor = colors.quietText
    recentList.quietTextColor = colors.quietText
  }

  private func focusFirstEmptyField() {
    let field = FileSlot.allCases.first { selection[$0] == nil }.flatMap { fields[$0] }
    window?.makeFirstResponder(field ?? fields[.left])
  }

  /// Lists the recent comparisons; with `fitting`, at the height of their lines, with the window
  /// at the height of its content.
  private func showRecentComparisons(fitting: Bool) {
    let comparisons = recentComparisons.comparisons
    recentList.show(comparisons, fitting: fitting)
    recentSection.isHidden = comparisons.isEmpty
    if fitting {
      fitWindowToContent()
    }
  }

  /// Sizes the window to its content and keeps its top edge in place.
  private func fitWindowToContent() {
    guard let window, let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    let top = window.frame.maxY
    var frame = window.frameRect(
      forContentRect: CGRect(origin: window.frame.origin, size: content.fittingSize))
    frame.origin.y = top - frame.height
    window.setFrame(frame, display: true)
  }

  @objc private func recentComparisonsDidChange(_ notification: Notification) {
    showRecentComparisons(fitting: window?.isVisible != true)
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    displayOptions = .current(in: .shared)
  }
}

extension CompareFilesWindowController: NSWindowDelegate {}

extension CompareFilesWindowController: NSUserInterfaceValidations {
  /// Swap Sides needs a file in an outer field; the other commands of the window always work.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(swapSides(_:)): selection[.left] != nil || selection[.right] != nil
    case #selector(openComparison(_:)): openButton.isEnabled
    default: true
    }
  }
}
