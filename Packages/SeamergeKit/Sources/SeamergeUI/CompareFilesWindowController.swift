import AppKit
import MergeModel

/// The sheet Compare Files, Merge Files or Change Files: fields for the files of a session in
/// their roles, and the default button that opens them.
///
/// To compare, it has two fields, Left and Right, which take two files or two folders; to merge,
/// three, A, Base and B, which take files. Change Files has the fields of the kind of its window
/// and takes no folders. The button opens the files in exactly the roles shown; if they cannot
/// be opened, a sheet on the sheet says why and the files stay. The sheet opens nothing by
/// itself, and the window it hangs on ends it once the files show.
@MainActor
final class CompareFilesWindowController: NSWindowController {
  /// What a sheet of files is for.
  enum Purpose: Equatable {
    /// Two files or two folders to compare in a window of their own.
    case compare

    /// Three files to merge in a window of their own.
    case merge

    /// Other files for a session window of `kind`; the kind stays.
    case change(Session.Kind)

    /// The kind of session the fields are for.
    var kind: Session.Kind {
      switch self {
      case .compare: .diff
      case .merge: .merge
      case .change(let kind): kind
      }
    }

    /// Whether the fields take folders, which only a comparison in a window of its own does.
    var acceptsFolders: Bool { self == .compare }

    /// The title of the sheet, which VoiceOver says.
    var title: String {
      switch self {
      case .compare: CompareFilesWindowController.compareFilesTitle
      case .merge: CompareFilesWindowController.mergeFilesTitle
      case .change:
        String(
          localized: "Change Files", bundle: .module,
          comment: "The title of the sheet that chooses other files for a session window.")
      }
    }

    /// The title of the default button.
    var openTitle: String {
      switch self {
      case .compare:
        String(
          localized: "Compare", bundle: .module,
          comment: "Sheet Compare Files: the default button, which compares the files.")
      case .merge:
        String(
          localized: "Merge", bundle: .module,
          comment: "Sheet Merge Files: the default button, which merges the files.")
      case .change:
        String(
          localized: "Change", bundle: .module,
          comment: "Sheet Change Files: the default button, which shows the files in the window.")
      }
    }
  }

  /// What the sheet is for.
  let purpose: Purpose

  /// The files in the fields.
  var selection: FileSelection {
    didSet {
      if selection != oldValue {
        showsUnsupportedSelection = false
      }
    }
  }

  /// Whether the sheet says what Seamerge compares, after it was handed a selection it does not
  /// compare; until the fields change.
  var showsUnsupportedSelection = false

  /// The fields, by their place.
  let fields: [FileSlot: FileField]

  /// The words below the fields, which say their roles.
  let captions: [FileSlot: NSTextField]

  /// The default button, Compare, Merge or Change, which opens the files in the fields.
  let openButton: NSButton

  /// The note beside the buttons that says why the fields cannot be opened, while they do not go
  /// together.
  let problemLabel = NSTextField(labelWithString: "")

  /// Whether the files of the fields are being opened.
  private(set) var isOpening = false

  /// The accessibility settings the sheet draws with.
  var displayOptions: DisplayOptions {
    didSet { applyColors() }
  }

  /// The fields that a drag going on now would fill, and the roles they would take.
  var dropTargets: [FileSlot: String] = [:] {
    didSet { showDropTargets() }
  }

  /// The open panel and the sheet of a failure.
  let panels: any CompareFilesPanels

  /// Tells VoiceOver what changed.
  let announce: (String) -> Void

  /// Opens the files of a comparison and returns once they show.
  ///
  /// - Throws: Why the files cannot be opened; the sheet shows it and keeps them.
  var onOpen: (FileComparison) async throws -> Void = { _ in }

  private let cancelButton: NSButton

  /// Creates the sheet for `purpose` in `window`, which draws with `displayOptions`, asks with
  /// `panels` and tells VoiceOver what changed through `announce`.
  init(
    purpose: Purpose, displayOptions: DisplayOptions, panels: any CompareFilesPanels,
    window: CompareFilesWindow, announce: @escaping (String) -> Void
  ) {
    self.purpose = purpose
    selection = FileSelection(kind: purpose.kind)
    self.displayOptions = displayOptions
    self.panels = panels
    self.announce = announce
    cancelButton = NSButton(
      title: String(
        localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."),
      target: nil, action: nil)
    let colors = CompareFilesColors(displayOptions)
    var fields: [FileSlot: FileField] = [:]
    var captions: [FileSlot: NSTextField] = [:]
    for slot in FileSlot.slots(for: purpose.kind) {
      fields[slot] = FileField(slot: slot, acceptsFolders: purpose.acceptsFolders, colors: colors)
      let caption = NSTextField(labelWithString: "")
      caption.alignment = .center
      caption.setAccessibilityElement(false)
      captions[slot] = caption
    }
    self.fields = fields
    self.captions = captions
    openButton = NSButton(title: purpose.openTitle, target: nil, action: nil)
    super.init(window: window)

    window.title = purpose.title
    window.contentView = makeContent()
    for field in fields.values {
      field.delegate = self
    }
    openButton.target = self
    openButton.action = #selector(openComparison(_:))
    openButton.keyEquivalent = "\r"
    cancelButton.target = self
    cancelButton.action = #selector(cancelOperation(_:))
    cancelButton.keyEquivalent = "\u{1B}"
    applyColors()
    selectionDidChange()
    window.contentView?.layoutSubtreeIfNeeded()
    window.setContentSize(window.contentView?.fittingSize ?? .zero)
  }

  /// Sheets of files are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  private func makeContent() -> NSView {
    let columns = selection.slots.compactMap { slot -> NSView? in
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
    problemLabel.lineBreakMode = .byTruncatingTail
    problemLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let buttonRow = NSStackView(views: [problemLabel, NSView(), cancelButton, openButton])
    buttonRow.distribution = .fill

    let stack = NSStackView(views: [fieldsRow, buttonRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = CompareFilesMetrics.sectionSpacing
    let margin = CompareFilesMetrics.margin
    stack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
    stack.translatesAutoresizingMaskIntoConstraints = false
    buttonRow.widthAnchor.constraint(equalTo: fieldsRow.widthAnchor).isActive = true

    let content = FileDropView()
    content.delegate = self
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
    return content
  }

  /// Puts `urls` in the fields as if they were dropped on the sheet and tells whether the sheet
  /// took them.
  @discardableResult
  func fill(with urls: [URL]) -> Bool {
    // A folder is known as one by its directory path; whatever cannot be looked at counts as a
    // file, which opening then reports.
    let entries = urls.map { FileDrop.entry(at: $0) ?? $0 }
    guard let places = places(for: entries, droppedOn: nil) else { return false }
    fill(places)
    return true
  }

  /// Puts the files of `comparison` in their fields.
  func fill(_ comparison: FileComparison) {
    var places: [FileSlot: URL] = [.left: comparison.left, .right: comparison.right]
    places[.base] = comparison.base
    selection.fill(places.filter { selection.slots.contains($0.key) })
    selectionDidChange()
  }

  /// Puts the files of `places` in their fields and tells VoiceOver where each went.
  func fill(_ places: [FileSlot: URL]) {
    selection.fill(places)
    selectionDidChange()
    announce(
      selection.slots.compactMap { slot in
        places[slot].map { url in
          String(
            localized: "\(url.lastPathComponent) added as \(selection.title(of: slot))",
            bundle: .module,
            comment: "VoiceOver: a file was put in a field, such as LoginView.swift added as Base.")
        }
      }.joined(separator: ". "))
  }

  /// Empties the field `slot` and tells VoiceOver.
  func clear(_ slot: FileSlot) {
    guard let url = selection[slot] else { return }
    let role = selection.title(of: slot)
    selection[slot] = nil
    selectionDidChange()
    announce(
      String(
        localized: "\(url.lastPathComponent) removed from \(role)", bundle: .module,
        comment: "VoiceOver: a field was emptied, such as LoginView.swift removed from Left."))
  }

  /// Empties the fields and says what Seamerge compares, until the fields change.
  func showUnsupportedSelection() {
    selection = FileSelection(kind: purpose.kind)
    showsUnsupportedSelection = true
    selectionDidChange()
  }

  /// Puts the focus on the first empty field, or on the first field if none is empty.
  func focusFirstEmptyField() {
    let field = selection.slots.first { selection[$0] == nil }.flatMap { fields[$0] }
    window?.makeFirstResponder(field ?? fields[.left])
  }

  /// Swaps the files of the outer fields.
  @objc func swapSides(_ sender: Any?) {
    selection.swap(.left, .right)
    selectionDidChange()
    announceSwap(of: .left, and: .right)
  }

  /// Opens the files of the fields in their roles.
  @objc func openComparison(_ sender: Any?) {
    guard let comparison = selection.comparison else { return }
    open(comparison)
  }

  /// Opens `comparison`; if it cannot be opened, says why in a sheet and keeps the files.
  private func open(_ comparison: FileComparison) {
    guard !isOpening, let window else { return }
    isOpening = true
    selectionDidChange()
    Task {
      defer {
        isOpening = false
        selectionDidChange()
      }
      do {
        try await onOpen(comparison)
      } catch {
        await panels.showFailure(error, in: window)
      }
    }
  }

  /// Ends the sheet without opening anything.
  @objc override func cancelOperation(_ sender: Any?) {
    guard let window else { return }
    window.sheetParent?.endSheet(window, returnCode: .cancel)
  }

  func announceSwap(of first: FileSlot, and second: FileSlot) {
    announce(
      String(
        localized: "Swapped \(selection.title(of: first)) and \(selection.title(of: second))",
        bundle: .module, comment: "VoiceOver: two fields swapped their files."))
  }

  /// Shows the files of the fields, the roles they have now and whether the button opens them.
  func selectionDidChange() {
    for slot in selection.slots {
      fields[slot]?.update(url: selection[slot], role: selection.title(of: slot))
    }
    showDropTargets()
    problemLabel.stringValue =
      selection.problem?.message
      ?? (showsUnsupportedSelection ? Self.unsupportedSelectionMessage : "")
    let comparison = selection.comparison
    openButton.isEnabled =
      !isOpening && comparison.map { purpose.acceptsFolders || !$0.comparesFolders } ?? false
  }

  /// Says below each field its role, or the role a drop would give it while one would fill it,
  /// next to the border of the field.
  private func showDropTargets() {
    for slot in selection.slots {
      fields[slot]?.isDropTarget = dropTargets[slot] != nil
      captions[slot]?.stringValue = dropTargets[slot] ?? selection.title(of: slot)
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
    problemLabel.textColor = colors.quietText
  }
}

extension CompareFilesWindowController {
  /// The title of the sheet Compare Files and of the command that shows it.
  nonisolated static var compareFilesTitle: String {
    String(
      localized: "Compare Files", bundle: .module,
      comment: "The title of the sheet that puts two files or folders together to compare.")
  }

  /// The title of the sheet Merge Files and of the command that shows it.
  nonisolated static var mergeFilesTitle: String {
    String(
      localized: "Merge Files", bundle: .module,
      comment: "The title of the sheet that puts three files together to merge.")
  }

  /// The sentence below the fields after the sheet was handed a selection it does not compare.
  static var unsupportedSelectionMessage: String {
    String(
      localized: "Seamerge compares two or three files, or two folders.", bundle: .module,
      comment:
        "Compare Files: below the fields after Compare with Seamerge in the Finder was used on a selection that Seamerge does not compare."
    )
  }
}

extension CompareFilesWindowController: NSUserInterfaceValidations {
  /// Swap Sides needs a file in an outer field; the other commands of the sheet always work.
  func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(swapSides(_:)): selection[.left] != nil || selection[.right] != nil
    case #selector(openComparison(_:)): openButton.isEnabled
    default: true
    }
  }
}
