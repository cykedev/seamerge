import AppKit

/// The column of the welcome window that carries the name of the app: its icon, name and
/// version on the deep blue of the website, the buttons that start a comparison or a merge, and
/// at the bottom the place to drop files.
///
/// The column draws in the dark appearance whatever the appearance of the window, so that the
/// buttons and their focus ring are made for the dark blue behind them.
final class WelcomeSidebar: NSView {
  /// Shows the sheet Compare Files; the default button of the window.
  let compareFilesButton: NSButton

  /// Lets the user choose two folders to compare.
  let compareFoldersButton: NSButton

  /// Shows the sheet Merge Files.
  let mergeFilesButton: NSButton

  /// The place at the bottom that invites files and shows when a drag would be taken.
  let dropArea: WelcomeDropArea

  /// The colors the column draws with.
  var colors: WelcomeColors {
    didSet { applyColors() }
  }

  private let nameLabel: NSTextField
  private let versionLabel: NSTextField

  /// Creates the column with the icon `icon` and the version `version`, drawn in `colors`.
  init(icon: NSImage, version: String?, colors: WelcomeColors) {
    self.colors = colors
    compareFilesButton = Self.button(
      CompareFilesWindowController.compareFilesTitle + "…", symbol: Self.compareSymbol)
    compareFoldersButton = Self.button(
      String(
        localized: "Compare Folders…", bundle: .module,
        comment: "Welcome window: the button that chooses two folders to compare."),
      symbol: Self.foldersSymbol)
    mergeFilesButton = Self.button(
      CompareFilesWindowController.mergeFilesTitle + "…", symbol: Self.mergeSymbol)
    dropArea = WelcomeDropArea(colors: colors)
    nameLabel = NSTextField(labelWithString: "Seamerge")
    versionLabel = NSTextField(
      labelWithString: version.map {
        String(
          localized: "Version \($0)", bundle: .module,
          comment: "Welcome window: the version of the app below its name, such as Version 0.6.0.")
      } ?? "")
    super.init(frame: .zero)
    appearance = NSAppearance(named: .darkAqua)
    compareFilesButton.keyEquivalent = "\r"
    setUpContent(icon: icon)
    applyColors()
  }

  /// The column is made in code only.
  required init?(coder: NSCoder) {
    nil
  }

  /// The symbol of a comparison of two files, on its button and in the recent comparisons.
  static let compareSymbol = "doc.on.doc"

  /// The symbol of a comparison of two folders.
  static let foldersSymbol = "folder"

  /// The symbol of a merge.
  static let mergeSymbol = "arrow.triangle.merge"

  private static func button(_ title: String, symbol: String) -> NSButton {
    let button = NSButton(title: title, target: nil, action: nil)
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.imagePosition = .imageLeading
    button.imageHugsTitle = true
    button.controlSize = .large
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  private func setUpContent(icon: NSImage) {
    let iconView = NSImageView(image: icon)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    iconView.setAccessibilityElement(false)
    nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    versionLabel.font = .preferredFont(forTextStyle: .subheadline)
    versionLabel.isSelectable = true
    let header = NSStackView(views: [iconView, nameLabel, versionLabel])
    header.orientation = .vertical
    header.spacing = WelcomeMetrics.nameSpacing
    header.setCustomSpacing(WelcomeMetrics.nameSpacing * 3, after: iconView)

    let actions = NSStackView(views: [compareFilesButton, compareFoldersButton, mergeFilesButton])
    actions.orientation = .vertical
    actions.spacing = WelcomeMetrics.actionSpacing
    for button in actions.arrangedSubviews {
      button.widthAnchor.constraint(equalTo: actions.widthAnchor).isActive = true
    }

    let inset = WelcomeMetrics.sidebarInset
    for view in [header, actions, dropArea] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: WelcomeMetrics.iconSize),
      iconView.heightAnchor.constraint(equalToConstant: WelcomeMetrics.iconSize),
      header.topAnchor.constraint(equalTo: topAnchor, constant: WelcomeMetrics.titleBarHeight),
      header.centerXAnchor.constraint(equalTo: centerXAnchor),
      actions.topAnchor.constraint(
        equalTo: header.bottomAnchor, constant: WelcomeMetrics.actionsSpacing),
      actions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      dropArea.topAnchor.constraint(greaterThanOrEqualTo: actions.bottomAnchor, constant: inset),
      dropArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      dropArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      dropArea.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
      dropArea.heightAnchor.constraint(equalToConstant: WelcomeMetrics.dropAreaHeight),
    ])
  }

  private func applyColors() {
    nameLabel.textColor = colors.text
    versionLabel.textColor = colors.quietText
    dropArea.colors = colors
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    if colors.background.count > 1, let gradient = NSGradient(colors: colors.background) {
      gradient.draw(in: bounds, angle: WelcomeColors.gradientAngle)
    } else {
      (colors.background.first ?? WelcomeColors.deepBlue).setFill()
      bounds.fill()
    }
  }

  override var isOpaque: Bool { true }

  /// Lets the window be moved by its background, as the title bar lies over the column.
  override var mouseDownCanMoveWindow: Bool { true }
}

/// The place at the bottom of the welcome window that invites two files or folders to be
/// dropped anywhere on the window: quiet until a drag over the window would be taken, then
/// outlined and filled, with words that say what the drop does.
final class WelcomeDropArea: NSView {
  /// The colors the place draws with.
  var colors: WelcomeColors {
    didSet { applyColors() }
  }

  /// What a drag over the window would do, such as Drop to Compare, or `nil` while there is no
  /// drag that the window would take.
  var dropAction: String? {
    didSet {
      label.stringValue = dropAction ?? Self.invitation
      applyColors()
    }
  }

  private let symbolView = NSImageView()
  private let label = NSTextField(labelWithString: WelcomeDropArea.invitation)

  /// Creates the place, quiet, drawn in `colors`.
  init(colors: WelcomeColors) {
    self.colors = colors
    super.init(frame: .zero)
    symbolView.image = NSImage(
      systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
    symbolView.symbolConfiguration = .init(textStyle: .title2)
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.alignment = .center
    let stack = NSStackView(views: [symbolView, label])
    stack.orientation = .vertical
    stack.spacing = WelcomeMetrics.nameSpacing * 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    applyColors()
  }

  /// The place is made in code only.
  required init?(coder: NSCoder) {
    nil
  }

  /// The words of the place while nothing is dragged.
  static var invitation: String {
    String(
      localized: "Drop two files or folders", bundle: .module,
      comment: "Welcome window: the place that invites files dropped on the window.")
  }

  private func applyColors() {
    let color = dropAction == nil ? colors.quietText : colors.text
    label.textColor = color
    symbolView.contentTintColor = color
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let isTarget = dropAction != nil
    let width =
      isTarget
      ? WelcomeMetrics.dropAreaBorderWidth.target : WelcomeMetrics.dropAreaBorderWidth.quiet
    let radius = WelcomeMetrics.dropAreaCornerRadius
    let outline = NSBezierPath(
      roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
    if isTarget {
      colors.dropAreaTargetFill.setFill()
      outline.fill()
    }
    outline.lineWidth = width
    (isTarget ? colors.dropAreaTargetBorder : colors.dropAreaBorder).setStroke()
    outline.stroke()
  }

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityRole() -> NSAccessibility.Role? { .staticText }

  override func accessibilityLabel() -> String? { label.stringValue }

  override func accessibilityChildren() -> [Any]? { nil }
}
