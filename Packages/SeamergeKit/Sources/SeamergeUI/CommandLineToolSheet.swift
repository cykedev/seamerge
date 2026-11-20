import AppKit
import Integration

/// The sheet Install the seamerge Command: it says what lies at the place of the command and
/// offers to install, update or remove the link, built like the sheet of the Git setup.
///
/// The command for typing it by hand is folded away under Show Command, with a button that
/// copies it. If the change fails, the sheet stays open and says why next to its buttons.
@MainActor
final class CommandLineToolSheet: NSWindowController {
  /// The status the sheet was made for.
  let status: CommandLineToolStatus

  /// Carries out the change and returns why it failed, or `nil` once it is done.
  var onConfirm: (CommandLineToolChange) async -> CommandLineToolFailure? = { _ in nil }

  /// Ends the sheet, with the change it made, or `nil` if it made none.
  var onEnd: (CommandLineToolChange?) -> Void = { _ in }

  /// The button of the offer: Install, Update or Remove; `nil` once Homebrew installed the
  /// command.
  let confirmButton: NSButton?

  /// The button that ends the sheet without a change: Cancel, or OK where nothing is offered.
  let cancelButton: NSButton

  /// The default button.
  let defaultButton: NSButton

  /// The triangle of Show Command, if the sheet offers to make the link.
  let commandsDisclosure: NSButton

  /// The commands, the button Copy and the sentence about the `PATH`, shown once the triangle
  /// is open.
  let commandsView: NSStackView

  /// The text of the commands.
  let commandsText: NSTextView

  /// Why the last change failed, next to the buttons.
  let failureLabel: NSTextField

  /// What the shell said about the failure, below the buttons.
  let failureDetailLabel: NSTextField

  /// Turns next to the buttons while the change waits for the dialog of macOS.
  let progressIndicator = NSProgressIndicator()

  /// The paragraphs of the sheet, from top to bottom.
  private(set) var paragraphs: [NSTextField] = []

  private let commands: [String]
  private let pasteboard: NSPasteboard

  /// Creates the sheet for `status`, drawing quiet text with `colors`, which copies to
  /// `pasteboard`.
  init(
    status: CommandLineToolStatus, colors: CompareFilesColors, pasteboard: NSPasteboard = .general
  ) {
    self.status = status
    self.pasteboard = pasteboard
    commands = CommandLineToolChange.typedCommands(for: status)
    confirmButton = Self.confirmTitle(of: status.offer).map {
      NSButton(title: $0, target: nil, action: nil)
    }
    cancelButton = NSButton(
      title: status.offer == .none
        ? String(
          localized: "OK", bundle: .module,
          comment: "Install the seamerge Command: the button that closes the sheet.")
        : String(
          localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."),
      target: nil, action: nil)
    defaultButton =
      status.offer == .remove || status.offer == .none
      ? cancelButton : confirmButton ?? cancelButton
    commandsDisclosure = NSButton(title: "", target: nil, action: nil)
    commandsText = NSTextView()
    commandsView = NSStackView()
    failureLabel = NSTextField(wrappingLabelWithString: "")
    failureDetailLabel = NSTextField(wrappingLabelWithString: "")
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: CGSize(width: Metrics.width, height: 200)),
      styleMask: [.titled], backing: .buffered, defer: true)
    super.init(window: window)
    window.contentView = makeContent(colors: colors)
    window.setAccessibilityTitle(status.sheetTitle)
    window.contentView?.layoutSubtreeIfNeeded()
    if let fitting = window.contentView?.fittingSize {
      window.setContentSize(fitting)
    }
    window.initialFirstResponder = defaultButton
  }

  /// Sheets are never archived.
  required init?(coder: NSCoder) {
    nil
  }

  private static func confirmTitle(of offer: CommandLineToolStatus.Offer) -> String? {
    switch offer {
    case .install:
      String(
        localized: "Install", bundle: .module,
        comment: "Install the seamerge Command: the button that makes the link.")
    case .update:
      String(
        localized: "Update", bundle: .module,
        comment: "Install the seamerge Command: the button that points the link to this copy.")
    case .remove:
      String(
        localized: "Remove", bundle: .module,
        comment: "Install the seamerge Command: the button that deletes the link.")
    case .none: nil
    }
  }

  private func makeContent(colors: CompareFilesColors) -> NSView {
    let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
    icon.setAccessibilityElement(false)
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
      icon.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
    ])

    let title = paragraph(status.sheetTitle)
    title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    var rows: [NSView] = [title, paragraph(status.sheetMessage)]
    if let otherFile = status.otherFileText {
      rows.append(paragraph(otherFile))
    }
    if status.showsCommands {
      rows.append(makeDisclosureRow())
      rows.append(makeCommandsView(colors: colors))
    }
    if let problem = status.problemText {
      rows.append(paragraph(problem))
    }

    let text = NSStackView(views: rows)
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = Metrics.paragraphSpacing
    text.setCustomSpacing(Metrics.titleSpacing, after: title)
    for row in rows {
      row.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
    }
    text.widthAnchor.constraint(equalToConstant: Metrics.textWidth).isActive = true
    let top = NSStackView(views: [icon, text])
    top.alignment = .top
    top.spacing = Metrics.iconSpacing

    failureLabel.isHidden = true
    progressIndicator.style = .spinning
    progressIndicator.controlSize = .small
    progressIndicator.isHidden = true
    progressIndicator.setAccessibilityLabel(
      String(
        localized: "Waiting for macOS", bundle: .module,
        comment: "VoiceOver: the change waits for the dialog of macOS that asks for a password."))
    failureLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    failureLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    failureDetailLabel.isHidden = true
    failureDetailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    failureDetailLabel.textColor = colors.quietText
    failureDetailLabel.isSelectable = true
    let buttons: [NSView] =
      switch (status.offer, confirmButton) {
      case (.remove, let confirmButton?):
        [failureLabel, progressIndicator, NSView(), confirmButton, cancelButton]
      case (_, let confirmButton?):
        [failureLabel, progressIndicator, NSView(), cancelButton, confirmButton]
      case (_, nil): [NSView(), cancelButton]
      }
    let buttonRow = NSStackView(views: buttons)
    buttonRow.distribution = .fill
    buttonRow.spacing = Metrics.buttonSpacing
    confirmButton?.target = self
    confirmButton?.action = #selector(confirm(_:))
    confirmButton?.isEnabled = status.canConfirm
    cancelButton.target = self
    cancelButton.action = #selector(cancelOperation(_:))
    defaultButton.keyEquivalent = "\r"
    if defaultButton !== cancelButton {
      cancelButton.keyEquivalent = "\u{1B}"
    }

    let stack = NSStackView(views: [top, buttonRow, failureDetailLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = Metrics.sectionSpacing
    stack.setCustomSpacing(Metrics.paragraphSpacing, after: buttonRow)
    let margin = Metrics.margin
    stack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
    stack.translatesAutoresizingMaskIntoConstraints = false
    for row in [top, buttonRow, failureDetailLabel] {
      row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * margin).isActive = true
    }
    let content = NSView()
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      stack.widthAnchor.constraint(equalToConstant: Metrics.width),
    ])
    return content
  }

  private func paragraph(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.lineBreakMode = .byWordWrapping
    paragraphs.append(label)
    return label
  }

  private func makeDisclosureRow() -> NSView {
    let title = String(
      localized: "Show Command", bundle: .module,
      comment: "Install the seamerge Command: the triangle that shows the command to type.")
    commandsDisclosure.bezelStyle = .disclosure
    commandsDisclosure.setButtonType(.pushOnPushOff)
    commandsDisclosure.state = .off
    commandsDisclosure.target = self
    commandsDisclosure.action = #selector(toggleCommands(_:))
    commandsDisclosure.setAccessibilityLabel(title)
    let label = NSTextField(labelWithString: title)
    label.setAccessibilityElement(false)
    let row = NSStackView(views: [commandsDisclosure, label])
    row.spacing = Metrics.disclosureSpacing
    return row
  }

  private func makeCommandsView(colors: CompareFilesColors) -> NSView {
    commandsText.string = commands.joined(separator: "\n")
    commandsText.font = .monospacedSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: .regular)
    commandsText.isEditable = false
    commandsText.isSelectable = true
    commandsText.textContainerInset = CGSize(
      width: Metrics.commandsInset, height: Metrics.commandsInset)
    commandsText.setAccessibilityLabel(
      String(
        localized: "Command", bundle: .module,
        comment: "VoiceOver: the command to type in Install the seamerge Command."))
    let scrollView = NSScrollView()
    scrollView.documentView = commandsText
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    commandsText.autoresizingMask = [.width]
    commandsText.minSize = .zero
    commandsText.maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    commandsText.isVerticallyResizable = true
    commandsText.textContainer?.widthTracksTextView = true
    scrollView.heightAnchor.constraint(equalToConstant: Metrics.commandsHeight).isActive = true

    let note = paragraph(status.pathNote)
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = colors.quietText
    let copy = NSButton(
      title: String(
        localized: "Copy", bundle: .module,
        comment: "Install the seamerge Command: the button that copies the command."),
      target: self, action: #selector(copyCommands(_:)))
    copy.toolTip = String(
      localized: "Copy the command to paste it into Terminal", bundle: .module,
      comment: "Tooltip of the button Copy in Install the seamerge Command.")
    note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let noteRow = NSStackView(views: [note, copy])
    noteRow.alignment = .firstBaseline
    noteRow.spacing = Metrics.buttonSpacing
    commandsView.setViews([scrollView, noteRow], in: .top)
    commandsView.orientation = .vertical
    commandsView.alignment = .leading
    commandsView.spacing = Metrics.paragraphSpacing
    for row in [scrollView, noteRow] {
      row.widthAnchor.constraint(equalTo: commandsView.widthAnchor).isActive = true
    }
    commandsView.isHidden = true
    return commandsView
  }

  /// Shows or hides the command; the sheet grows in height to make room.
  @objc func toggleCommands(_ sender: Any?) {
    commandsView.isHidden = commandsDisclosure.state == .off
    fitWindow()
  }

  /// Puts the commands on the pasteboard, one per line.
  @objc func copyCommands(_ sender: Any?) {
    pasteboard.clearContents()
    pasteboard.setString(commands.joined(separator: "\n") + "\n", forType: .string)
  }

  /// Carries out the change; on success ends the sheet, and otherwise says why and stays open.
  @objc func confirm(_ sender: Any?) {
    Task { await carryOut() }
  }

  /// Carries out the change of the button and returns once the sheet has ended or says why it
  /// failed.
  func carryOut() async {
    guard let change = status.change, confirmButton?.isEnabled == true else { return }
    setBusy(true)
    let failure = await onConfirm(change)
    setBusy(false)
    guard let failure else {
      onEnd(change)
      return
    }
    show(failure)
  }

  /// Ends the sheet without a change.
  @objc override func cancelOperation(_ sender: Any?) {
    guard cancelButton.isEnabled else { return }
    onEnd(nil)
  }

  private func show(_ failure: CommandLineToolFailure) {
    failureLabel.stringValue = failure.errorDescription ?? ""
    failureLabel.isHidden = false
    failureDetailLabel.stringValue = failure.failureReason ?? ""
    failureDetailLabel.isHidden = failure.failureReason == nil
    NSAccessibility.post(
      element: failureLabel, notification: .announcementRequested,
      userInfo: [.announcement: failureLabel.stringValue])
    fitWindow()
  }

  /// Locks the buttons and turns the indicator while the change runs, and frees them after.
  private func setBusy(_ isBusy: Bool) {
    confirmButton?.isEnabled = !isBusy && status.canConfirm
    cancelButton.isEnabled = !isBusy
    progressIndicator.isHidden = !isBusy
    if isBusy {
      failureLabel.isHidden = true
      failureDetailLabel.isHidden = true
      progressIndicator.startAnimation(nil)
    } else {
      progressIndicator.stopAnimation(nil)
    }
  }

  /// Gives the window the height of its content and keeps its top edge in place.
  private func fitWindow() {
    guard let window, let content = window.contentView else { return }
    content.layoutSubtreeIfNeeded()
    let top = window.frame.maxY
    var frame = window.frameRect(
      forContentRect: CGRect(origin: window.frame.origin, size: content.fittingSize))
    frame.origin.y = top - frame.height
    window.setFrame(frame, display: true, animate: false)
  }

  /// The sizes and distances of the sheet, on the 4-point grid, as in the sheet of the Git setup.
  private enum Metrics {
    static let width: CGFloat = 520
    static let margin: CGFloat = 20
    static let iconSize: CGFloat = 64
    static let iconSpacing: CGFloat = 16
    static var textWidth: CGFloat { width - 2 * margin - iconSize - iconSpacing }
    static let titleSpacing: CGFloat = 12
    static let paragraphSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 20
    static let buttonSpacing: CGFloat = 12
    static let disclosureSpacing: CGFloat = 4
    static let commandsHeight: CGFloat = 64
    static let commandsInset: CGFloat = 4
  }
}
