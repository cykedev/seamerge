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
///
/// Paste puts what the clipboard holds in the field with the focus, or else in the first empty
/// one: files as if dropped there, and to compare, text as a side named Clipboard, whose copy the
/// sheet keeps until a window takes it, no field holds it or the sheet ends.
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

    /// Whether the fields take text pasted from the clipboard, which only a comparison in a
    /// window of its own does: a merge needs a file to write to.
    var acceptsText: Bool { self == .compare }

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

  /// The clipboard that Paste reads.
  let pasteboard: NSPasteboard

  /// Where pasted text is kept, or `nil` for a sheet that takes only files.
  let pastedTextCache: PastedTextCache?

  /// The copies of text pasted into the sheet that no window has taken yet.
  private var ownPastedTexts: [URL: PastedText] = [:]

  /// Whether the sheet has ended.
  private var hasEnded = false

  /// Opens the files of a comparison and returns once they show.
  ///
  /// - Throws: Why the files cannot be opened; the sheet shows it and keeps them.
  var onOpen: (FileComparison) async throws -> Void = { _ in }

  private let cancelButton: NSButton

  /// Creates the sheet for `purpose` in `window`, which draws with `displayOptions`, asks with
  /// `panels`, pastes from `pasteboard`, keeps pasted text in `pastedTextCache` and tells
  /// VoiceOver what changed through `announce`.
  ///
  /// A sheet whose purpose takes text needs a cache; the others take only files and need none.
  init(
    purpose: Purpose, displayOptions: DisplayOptions, panels: any CompareFilesPanels,
    pasteboard: NSPasteboard, pastedTextCache: PastedTextCache? = nil,
    window: CompareFilesWindow, announce: @escaping (String) -> Void
  ) {
    self.purpose = purpose
    selection = FileSelection(kind: purpose.kind)
    self.displayOptions = displayOptions
    self.panels = panels
    precondition(
      !purpose.acceptsText || pastedTextCache != nil, "A sheet that takes text needs a cache")
    self.pasteboard = pasteboard
    self.pastedTextCache = purpose.acceptsText ? pastedTextCache : nil
    self.announce = announce
    cancelButton = NSButton(
      title: String(
        localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."),
      target: nil, action: nil)
    let colors = CompareFilesColors(displayOptions)
    var fields: [FileSlot: FileField] = [:]
    var captions: [FileSlot: NSTextField] = [:]
    for slot in FileSlot.slots(for: purpose.kind) {
      fields[slot] = FileField(
        slot: slot, acceptsFolders: purpose.acceptsFolders,
        acceptsText: purpose.acceptsText, colors: colors)
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

  /// Puts the files of `comparison` in their fields, pasted text as such.
  func fill(_ comparison: FileComparison) {
    selection.fill(comparison)
    selectionDidChange()
  }

  /// Puts the files of `places` in their fields and tells VoiceOver where each went.
  func fill(_ places: [FileSlot: URL]) {
    selection.fill(places)
    selectionDidChange()
    announceAdding(places.mapValues(\.lastPathComponent))
  }

  /// Tells VoiceOver which name went into which field, by `names`.
  private func announceAdding(_ names: [FileSlot: String]) {
    announce(
      selection.slots.compactMap { slot in
        names[slot].map { name in
          String(
            localized: "\(name) added as \(selection.title(of: slot))", bundle: .module,
            comment: "VoiceOver: a file was put in a field, such as LoginView.swift added as Base.")
        }
      }.joined(separator: ". "))
  }

  /// What Paste would do now: put files in the fields as if dropped on the field with the focus,
  /// or text in the field with the focus, or else in the first empty one; `nil` if the clipboard
  /// holds nothing the fields take or no field is left for it.
  ///
  /// The text itself is not read: each check of Paste asks this.
  private var pasting: Pasting? {
    switch ClipboardContent.available(on: pasteboard) {
    case .files(let urls):
      return places(for: urls, droppedOn: focusedSlot).map(Pasting.files)
    case .text:
      return textSlot.map(Pasting.text)
    case nil:
      return nil
    }
  }

  /// The field of the sheet that has the focus, if one has.
  private var focusedSlot: FileSlot? {
    (window?.firstResponder as? FileField).flatMap { field in
      fields[field.slot] === field ? field.slot : nil
    }
  }

  /// The field that pasted text goes into, if the sheet takes text and a field is left for it.
  private var textSlot: FileSlot? {
    pastedTextCache == nil ? nil : selection.place(forTextPastedOn: focusedSlot)
  }

  /// What Paste does.
  private enum Pasting {
    /// Puts files in fields.
    case files([FileSlot: URL])

    /// Reads the text, keeps it in the cache and puts it in the field.
    case text(into: FileSlot)
  }

  /// Puts what the clipboard holds in the field with the focus, or else in the first empty one:
  /// files as if dropped on the field, and text as a side named Clipboard; says why if the text
  /// cannot be kept.
  @objc func paste(_ sender: Any?) {
    switch pasting {
    case .files(let places):
      fill(places)
    case .text:
      guard let text = ClipboardContent.text(on: pasteboard) else {
        NSSound.beep()
        return
      }
      paste(text: text)
    case nil:
      NSSound.beep()
    }
  }

  /// Puts `text`, read from the clipboard, in the field with the focus, or else in the first
  /// empty one, as a side named Clipboard; says why if it cannot be kept.
  func paste(text: String) {
    guard let pastedTextCache, let slot = textSlot else {
      NSSound.beep()
      return
    }
    do {
      paste(try pastedTextCache.keep(text, pastedAt: .now), into: slot)
    } catch {
      guard let window else { return }
      Task { await panels.showFailure(error, in: window) }
    }
  }

  /// Puts `text`, kept from the clipboard, in the field `slot` and tells VoiceOver.
  private func paste(_ text: PastedText, into slot: FileSlot) {
    ownPastedTexts[text.url] = text
    selection.paste(text, into: slot)
    selectionDidChange()
    announceAdding([slot: PastedText.name])
  }

  /// Ends what the sheet keeps once it has ended: the copies of pasted text that no window took
  /// go, at once or once the files being opened show.
  func didEnd() {
    hasEnded = true
    removeUnusedPastedTexts()
  }

  /// Removes the copies of text pasted into the sheet that no field holds any longer, or every
  /// one that no window took once the sheet has ended; while files are being opened, they wait
  /// for the window, which may take them.
  private func removeUnusedPastedTexts() {
    guard !isOpening else { return }
    for (url, text) in ownPastedTexts where hasEnded || selection.pastedTexts[url] == nil {
      text.remove()
      ownPastedTexts[url] = nil
    }
  }

  /// Empties the field `slot` and tells VoiceOver.
  func clear(_ slot: FileSlot) {
    guard let url = selection[slot] else { return }
    let name = selection.pastedText(in: slot) == nil ? url.lastPathComponent : PastedText.name
    let role = selection.title(of: slot)
    selection[slot] = nil
    selectionDidChange()
    announce(
      String(
        localized: "\(name) removed from \(role)", bundle: .module,
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
        // The window of the comparison removes these copies as it closes.
        for url in comparison.pastedTexts.keys {
          ownPastedTexts[url] = nil
        }
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
      fields[slot]?.update(
        url: selection[slot], pastedText: selection.pastedText(in: slot),
        role: selection.title(of: slot))
    }
    removeUnusedPastedTexts()
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
  /// Swap Sides needs a file in an outer field, and Paste something on the clipboard that a
  /// field takes; the other commands of the sheet always work.
  func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(swapSides(_:)): selection[.left] != nil || selection[.right] != nil
    case #selector(paste(_:)): pasting != nil
    case #selector(openComparison(_:)): openButton.isEnabled
    default: true
    }
  }
}
