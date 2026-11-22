import AppKit
import FolderCompare
import PaneKit

/// A row of the file list: the sign of what happened to the file, its name, and a dot while it
/// has copied changes that are not saved.
///
/// A file that only changed has no sign, since most files of a list did; its name lines up with
/// the others all the same. The dot stands at the end of the row, and in a wide list no further
/// from the start than in a sidebar of the standard width, unless the name pushes it on.
@MainActor
final class FileListCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("FileListCell")

  private let sign = NSImageView()

  /// The name of the file, shortened in its middle where the row is too narrow for it.
  let name = NSTextField(labelWithString: "")

  /// The dot of a file with copied changes that are not saved.
  let changedDot = NSImageView()

  /// Where the dot stands while it shows.
  private var dotConstraints: [NSLayoutConstraint] = []

  init() {
    super.init(frame: .zero)
    identifier = Self.identifier
    sign.setAccessibilityElement(false)
    name.lineBreakMode = .byTruncatingMiddle
    name.font = .preferredFont(forTextStyle: .body)
    name.textColor = .labelColor
    name.setAccessibilityElement(false)
    // The name pushes the dot on beyond its column, but gives way to the end of the row.
    name.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal)
    name.setContentHuggingPriority(.required, for: .horizontal)
    // The dot of a document with unsaved changes, as in the close button: a template image that
    // takes the color of the text, also in a selected row.
    changedDot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: WindowMetrics.changedFileDotSize, weight: .regular))
    changedDot.setAccessibilityElement(false)
    for view in [sign, name, changedDot] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    imageView = sign
    textField = name
    let spacing = WindowMetrics.fileRowSpacing
    let end = WindowMetrics.changedFileDotInset
    let atTheEnd = changedDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -end)
    atTheEnd.priority = .defaultHigh - 50
    let inTheColumn = changedDot.trailingAnchor.constraint(
      lessThanOrEqualTo: leadingAnchor, constant: WindowMetrics.sidebarWidth - end)
    inTheColumn.priority = .defaultHigh
    dotConstraints = [
      changedDot.leadingAnchor.constraint(
        greaterThanOrEqualTo: name.trailingAnchor, constant: spacing),
      changedDot.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -end),
      inTheColumn, atTheEnd,
    ]
    NSLayoutConstraint.activate([
      sign.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WindowMetrics.fileRowInset),
      sign.centerYAnchor.constraint(equalTo: centerYAnchor),
      sign.widthAnchor.constraint(equalToConstant: WindowMetrics.fileSignWidth),
      name.leadingAnchor.constraint(equalTo: sign.trailingAnchor, constant: spacing),
      name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -end),
      name.centerYAnchor.constraint(equalTo: centerYAnchor),
      changedDot.centerYAnchor.constraint(equalTo: centerYAnchor),
      changedDot.widthAnchor.constraint(equalToConstant: WindowMetrics.changedFileDotSize),
      changedDot.heightAnchor.constraint(equalToConstant: WindowMetrics.changedFileDotSize),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Shows `file` with the sign of what happened to it in the colors of `theme`, and a dot if it
  /// `isChanged`; VoiceOver reads its name, its folder, what happened and Edited.
  func show(_ file: CollectedFile, isChanged: Bool, theme: Theme) {
    let path = file.path as NSString
    name.stringValue = path.lastPathComponent
    changedDot.isHidden = !isChanged
    // A hidden dot takes no room from the name.
    if isChanged {
      NSLayoutConstraint.activate(dotConstraints)
    } else {
      NSLayoutConstraint.deactivate(dotConstraints)
    }
    let presentation = file.change.presentation
    sign.image = presentation.symbolName.flatMap {
      NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(scale: .medium))
    }
    sign.contentTintColor = presentation.color(in: theme)
    toolTip = presentation.toolTip(for: file.path)
    setAccessibilityLabel(
      [
        path.lastPathComponent, path.deletingLastPathComponent, presentation.word,
        isChanged ? SideHeader.editedText : "",
      ]
      .filter { !$0.isEmpty }.joined(separator: ", "))
  }
}

/// The heading of a folder in the file list: the folder relative to the top, quiet and
/// semibold, shortened in its middle, whose help tag shows it whole.
@MainActor
final class FolderHeadingCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("FolderHeadingCell")

  private let label = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    identifier = Self.identifier
    label.font = .systemFont(
      ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
    // Folders of a project often differ near the start (src/main against src/test) and are named
    // by their end; the middle is what they share.
    label.lineBreakMode = .byTruncatingMiddle
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    label.setAccessibilityElement(false)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WindowMetrics.fileRowInset),
      label.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor, constant: -WindowMetrics.changedFileDotInset),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
  }

  required init?(coder: NSCoder) {
    nil
  }

  /// Shows `folder` in `color`.
  func show(_ folder: String, color: NSColor) {
    label.stringValue = folder
    label.textColor = color
    toolTip = folder
    setAccessibilityLabel(
      String(
        localized: "Folder, \(folder)", bundle: .module,
        comment:
          "VoiceOver: the heading of a folder in the list of files, such as Folder, Sources/Orders."
      ))
  }
}

/// The row of the heading of a folder, which has the window background beneath it while it
/// stays at the top of the list, so that the rows scrolling beneath it do not show through it;
/// in its place it lets the sidebar show through as every row does.
@MainActor
final class FolderHeadingRowView: NSTableRowView {
  static let identifier = NSUserInterfaceItemIdentifier("FolderHeadingRowView")

  init() {
    super.init(frame: .zero)
    identifier = Self.identifier
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func drawBackground(in dirtyRect: NSRect) {
    guard isFloating else { return }
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }
}
