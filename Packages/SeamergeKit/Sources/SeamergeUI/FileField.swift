import AppKit
import UniformTypeIdentifiers

/// What a field of the sheet Compare Files asks of the sheet: to choose or clear its file, and
/// what to do with files dragged onto it.
@MainActor
protocol FileFieldDelegate: FileDropDelegate {
  /// The user wants to choose the file of `field`.
  func fileFieldDidAskToChoose(_ field: FileField)

  /// The user wants `field` to be empty.
  func fileFieldDidAskToClear(_ field: FileField)
}

/// A field of the sheet Compare Files: the place of one file in its role, which shows the file or
/// invites one.
///
/// It is built on its own because `NSPathControl` cannot show a file as a card with its icon,
/// name and folder, but it behaves like one: it takes files dragged onto it, chooses one with the
/// system's open panel, takes the focus with Tab, and tells VoiceOver its role and content.
/// Space chooses a file, Delete empties the field, a double click chooses as well; a filled field
/// can be dragged onto another to swap the two.
final class FileField: NSView {
  /// The field of the sheet that this view is.
  let slot: FileSlot

  /// Whether the field takes a folder as well as a file.
  let acceptsFolders: Bool

  /// Asked to choose, clear and take drops; the field does not retain it.
  weak var delegate: (any FileFieldDelegate)?

  /// The file in the field, if there is one.
  private(set) var url: URL?

  /// Whether a drop going on now would fill the field, which its border shows.
  var isDropTarget = false {
    didSet { needsDisplay = true }
  }

  /// The colors the field draws with.
  var colors: CompareFilesColors {
    didSet { applyColors() }
  }

  private var roleTitle = ""
  private let invitation: NSTextField
  private let chooseButton: NSButton
  private let emptyContent: NSStackView
  private let filledContent: NSStackView
  private let iconView = NSImageView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let folderLabel = NSTextField(labelWithString: "")
  private let clearButton: NSButton
  private var mouseDownEvent: NSEvent?

  /// Creates the field for `slot`, empty, which takes a folder if `acceptsFolders`, drawn in
  /// `colors`.
  init(slot: FileSlot, acceptsFolders: Bool, colors: CompareFilesColors) {
    self.slot = slot
    self.acceptsFolders = acceptsFolders
    self.colors = colors
    invitation = NSTextField(
      labelWithString: acceptsFolders
        ? String(
          localized: "Drop a File or Folder", bundle: .module,
          comment: "Compare Files: an empty field that takes a file or a folder.")
        : String(
          localized: "Drop a File", bundle: .module,
          comment: "Compare Files: an empty field, which takes a file dragged onto it."))
    invitation.alignment = .center
    chooseButton = NSButton(
      title: String(
        localized: "Choose…", bundle: .module,
        comment: "Compare Files: the button in an empty field that opens the open panel."),
      target: nil, action: nil)
    chooseButton.controlSize = .small
    chooseButton.refusesFirstResponder = true
    emptyContent = NSStackView(views: [invitation, chooseButton])
    clearButton = NSButton(
      image: NSImage(
        systemSymbolName: "xmark.circle.fill",
        accessibilityDescription: String(
          localized: "Remove File", bundle: .module,
          comment: "Compare Files: the button that empties a field."))
        ?? NSImage(),
      target: nil, action: nil)
    filledContent = NSStackView(views: [iconView, nameLabel, folderLabel])
    super.init(frame: CGRect(origin: .zero, size: CompareFilesMetrics.fieldSize))
    chooseButton.target = self
    chooseButton.action = #selector(choose(_:))
    clearButton.target = self
    clearButton.action = #selector(clear(_:))
    setUpContent()
    registerForDraggedTypes([.fileURL])
    focusRingType = .default
    applyColors()
    update(url: nil, role: "")
  }

  private func applyColors() {
    for label in [invitation, folderLabel] {
      label.textColor = colors.quietText
    }
    clearButton.contentTintColor = colors.quietText
    needsDisplay = true
  }

  /// Fields are made in code only.
  required init?(coder: NSCoder) {
    nil
  }

  private func setUpContent() {
    emptyContent.orientation = .vertical
    emptyContent.spacing = CompareFilesMetrics.fieldContentSpacing * 2
    filledContent.orientation = .vertical
    filledContent.spacing = CompareFilesMetrics.fieldContentSpacing
    for label in [nameLabel, folderLabel] {
      label.alignment = .center
      label.lineBreakMode = .byTruncatingMiddle
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    nameLabel.font = .systemFont(
      ofSize: NSFont.systemFontSize, weight: .medium)
    folderLabel.font = .preferredFont(forTextStyle: .subheadline)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    clearButton.isBordered = false
    clearButton.refusesFirstResponder = true
    clearButton.toolTip = String(
      localized: "Remove this file from the field", bundle: .module,
      comment: "Help tag of the button that empties a field of Compare Files.")

    for view in [emptyContent, filledContent, clearButton, iconView] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    for view in [emptyContent, filledContent, clearButton] as [NSView] {
      addSubview(view)
    }
    let inset = CompareFilesMetrics.fieldInset
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: CompareFilesMetrics.fieldSize.width),
      heightAnchor.constraint(equalToConstant: CompareFilesMetrics.fieldSize.height),
      emptyContent.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyContent.centerYAnchor.constraint(equalTo: centerYAnchor),
      filledContent.centerYAnchor.constraint(equalTo: centerYAnchor),
      filledContent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      filledContent.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      nameLabel.widthAnchor.constraint(equalTo: filledContent.widthAnchor),
      folderLabel.widthAnchor.constraint(equalTo: filledContent.widthAnchor),
      iconView.widthAnchor.constraint(equalToConstant: CompareFilesMetrics.iconSize),
      iconView.heightAnchor.constraint(equalToConstant: CompareFilesMetrics.iconSize),
      clearButton.topAnchor.constraint(
        equalTo: topAnchor, constant: CompareFilesMetrics.fieldContentSpacing * 2),
      clearButton.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -CompareFilesMetrics.fieldContentSpacing * 2),
      clearButton.widthAnchor.constraint(equalToConstant: WindowMetrics.minimumHitTarget),
      clearButton.heightAnchor.constraint(equalToConstant: WindowMetrics.minimumHitTarget),
    ])
  }

  /// Shows `url`, or invites a file when it is `nil`, in `role`, the word below the field.
  func update(url: URL?, role: String) {
    self.url = url
    roleTitle = role
    emptyContent.isHidden = url != nil
    filledContent.isHidden = url == nil
    clearButton.isHidden = url == nil
    if let url {
      let path = url.path(percentEncoded: false)
      iconView.image = NSWorkspace.shared.icon(
        for: url.hasDirectoryPath
          ? .folder : UTType(filenameExtension: url.pathExtension) ?? .data)
      nameLabel.stringValue = url.lastPathComponent
      folderLabel.stringValue = Self.folderName(of: url)
      toolTip = path
    } else {
      iconView.image = nil
      toolTip = nil
    }
    needsDisplay = true
  }

  /// The folder of `url` as the field shows it, with the home folder as a tilde.
  static func folderName(of url: URL) -> String {
    (url.deletingLastPathComponent().path(percentEncoded: false) as NSString)
      .abbreviatingWithTildeInPath
  }

  @objc private func choose(_ sender: Any?) {
    delegate?.fileFieldDidAskToChoose(self)
  }

  @objc private func clear(_ sender: Any?) {
    delegate?.fileFieldDidAskToClear(self)
  }

  /// The outline of the field.
  private var outline: NSBezierPath {
    let radius = CompareFilesMetrics.fieldCornerRadius
    return NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
  }

  override func draw(_ dirtyRect: NSRect) {
    let outline = outline
    if url != nil {
      colors.filledFieldFill.setFill()
      outline.fill()
    }
    if isDropTarget {
      let width = CompareFilesMetrics.dropTargetBorderWidth
      let radius = CompareFilesMetrics.fieldCornerRadius
      let border = NSBezierPath(
        roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius,
        yRadius: radius)
      border.lineWidth = width
      colors.dropTargetBorder.setStroke()
      border.stroke()
      return
    }
    (url == nil ? colors.emptyFieldBorder : colors.filledFieldBorder)
      .setStroke()
    outline.stroke()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  override func drawFocusRingMask() {
    outline.fill()
  }

  override var acceptsFirstResponder: Bool { true }

  override var canBecomeKeyView: Bool { true }

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.subtracting([.function, .numericPad]).isEmpty else {
      super.keyDown(with: event)
      return
    }
    switch event.charactersIgnoringModifiers {
    case " ":
      delegate?.fileFieldDidAskToChoose(self)
    case Self.delete, Self.forwardDelete:
      if url == nil {
        NSSound.beep()
      } else {
        delegate?.fileFieldDidAskToClear(self)
      }
    default:
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    mouseDownEvent = event
    if event.clickCount == 2 {
      delegate?.fileFieldDidAskToChoose(self)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let url, let mouseDownEvent else { return }
    self.mouseDownEvent = nil
    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
    item.setDraggingFrame(bounds, contents: snapshot())
    beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    mouseDownEvent = nil
  }

  /// The field as it looks now, to drag around.
  private func snapshot() -> NSImage? {
    guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    cacheDisplay(in: bounds, to: bitmap)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmap)
    return image
  }

  /// The characters AppKit gives Delete and Forward Delete.
  private static let delete = "\u{7F}"
  private static let forwardDelete = "\u{F728}"

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityRole() -> NSAccessibility.Role? { .button }

  override func accessibilityLabel() -> String? { roleTitle }

  override func accessibilityValue() -> Any? {
    guard let url else {
      return String(
        localized: "empty", bundle: .module, comment: "VoiceOver: a field without a file.")
    }
    return String(
      localized: "\(url.lastPathComponent), in \(Self.folderName(of: url))", bundle: .module,
      comment: "VoiceOver: the file in a field, such as LoginView.swift, in ~/Projects/app.")
  }

  override func accessibilityHelp() -> String? {
    acceptsFolders
      ? String(
        localized: "Choose a file or folder, or drop one here", bundle: .module,
        comment: "VoiceOver hint of a field of Compare Files that takes a folder as well.")
      : String(
        localized: "Choose a file, or drop one here", bundle: .module,
        comment: "VoiceOver hint of a field of Compare Files.")
  }

  override func accessibilityChildren() -> [Any]? { nil }

  override func accessibilityPerformPress() -> Bool {
    delegate?.fileFieldDidAskToChoose(self)
    return true
  }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    guard url != nil else { return nil }
    return [
      NSAccessibilityCustomAction(
        name: String(
          localized: "Remove File", bundle: .module,
          comment: "Compare Files: the button that empties a field.")
      ) { [weak self] in
        guard let self else { return false }
        delegate?.fileFieldDidAskToClear(self)
        return true
      }
    ]
  }
}

extension FileField: NSDraggingSource {
  /// A field can be dragged onto another field of its sheet, which swaps the two, and nowhere
  /// else: in the Finder, a drag would copy or move the file.
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }
}

extension FileField {
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    delegate?.operation(forDrag: sender, onto: slot) ?? []
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    delegate?.operation(forDrag: sender, onto: slot) ?? []
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    delegate?.dragDidEnd()
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    delegate?.acceptDrop(sender, onto: slot) ?? false
  }

  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    delegate?.dragDidEnd()
  }
}
