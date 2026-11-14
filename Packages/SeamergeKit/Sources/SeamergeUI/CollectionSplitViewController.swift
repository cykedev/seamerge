import AppKit

/// The content of a window that compares several files: the list of the files in a sidebar, and
/// beside it the panes and footer of the chosen file.
///
/// The sidebar shows once the window has two files, unless the user hid it, which every such
/// window remembers; before that, Show Sidebar does nothing.
@MainActor
final class CollectionSplitViewController: NSSplitViewController {
  /// The list of the files.
  let fileList: FileListViewController

  /// The item of the sidebar.
  let sidebarItem: NSSplitViewItem

  /// Whether the window has files enough for a list, two or more.
  var hasSeveralFiles = false {
    didSet {
      guard hasSeveralFiles != oldValue else { return }
      sidebarItem.isCollapsed = !(hasSeveralFiles && showsSidebarByChoice)
      sidebarDidChange()
    }
  }

  /// The least width of the panes beside the list.
  var minimumContentWidth: CGFloat {
    get { contentItem.minimumThickness }
    set { contentItem.minimumThickness = newValue }
  }

  /// Learns when the list comes into view or goes out of it.
  var sidebarDidChange: () -> Void = {}

  private let contentItem: NSSplitViewItem
  private let defaults: UserDefaults

  /// Creates the content with `fileList` in the sidebar and `content` beside it; `defaults`
  /// keep whether the user hid the sidebar.
  init(fileList: FileListViewController, content: NSViewController, defaults: UserDefaults) {
    self.fileList = fileList
    self.defaults = defaults
    sidebarItem = NSSplitViewItem(sidebarWithViewController: fileList)
    sidebarItem.minimumThickness = WindowMetrics.minimumSidebarWidth
    sidebarItem.maximumThickness = WindowMetrics.maximumSidebarWidth
    sidebarItem.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
    sidebarItem.isCollapsed = true
    contentItem = NSSplitViewItem(viewController: SafeAreaController(content: content))
    super.init(nibName: nil, bundle: nil)
    addSplitViewItem(sidebarItem)
    addSplitViewItem(contentItem)
  }

  /// Split views of a window are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  /// Hides the list, or shows it again, and remembers the choice for every such window.
  override func toggleSidebar(_ sender: Any?) {
    guard hasSeveralFiles else { return }
    let shows = sidebarItem.isCollapsed
    super.toggleSidebar(sender)
    showsSidebarByChoice = shows
    sidebarDidChange()
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    let isValid = super.validateUserInterfaceItem(item)
    return item.action == #selector(toggleSidebar(_:)) ? isValid && hasSeveralFiles : isValid
  }

  /// Whether the user wants the list in view; true until the user hides it.
  private var showsSidebarByChoice: Bool {
    get { !defaults.bool(forKey: Self.hidesSidebarKey) }
    set { defaults.set(!newValue, forKey: Self.hidesSidebarKey) }
  }

  private static let hidesSidebarKey = "HidesFileList"
}

/// Keeps the panes below the toolbar, which the sidebar beside them reaches up under.
@MainActor
private final class SafeAreaController: NSViewController {
  private let content: NSViewController

  init(content: NSViewController) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
    addChild(content)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let container = NSView()
    let contentView = content.view
    contentView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(contentView)
    NSLayoutConstraint.activate([
      contentView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
      contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    view = container
  }
}
