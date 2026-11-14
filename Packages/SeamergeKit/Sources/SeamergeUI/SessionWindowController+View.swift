import AppKit
import GitSupport
import MergeModel
import PaneKit

extension SessionWindowController {
  /// Hides the pane of the base, or shows it again; without a base it does nothing.
  @objc func toggleBase(_ sender: Any?) {
    guard canPerform(.toggleBase) else { return }
    let showsBase = !layout.showsBase
    let baseHadFocus = window?.firstResponder === layout.sourcePane(.base)?.documentView
    presentation.keepingTheLineOfBInPlace {
      layout.showsBase = showsBase
      presentation.showSourcesAgain()
    }
    if baseHadFocus, let b = layout.sourcePane(.b) {
      window?.makeFirstResponder(b.documentView)
    }
    updateMinimumSize()
    updateFooter()
  }

  /// Gives the result the whole window, or restores the layout; without a result it does
  /// nothing.
  @objc func toggleResultMaximized(_ sender: Any?) {
    guard canPerform(.toggleResultMaximized) else { return }
    let wasInBlockMode = isInBlockMode
    layout.maximizesResult.toggle()
    if layout.maximizesResult && wasInBlockMode {
      enterTextMode()
    }
    updateMinimumSize()
    updateFooter()
  }

  /// Turns the coupling of the panes while they scroll off or on.
  @objc func toggleScrollSynchronization(_ sender: Any?) {
    presentation.scrollSync.isEnabled.toggle()
    updateFooter()
  }

  /// Shows spaces, tabs and line endings as quiet symbols, or hides them.
  @objc func toggleInvisibles(_ sender: Any?) {
    let showsInvisibles = !isSwitchedOn(.toggleInvisibles)
    for pane in presentation.allPanes {
      pane.showsInvisibles = showsInvisibles
    }
    updateFooter()
  }

  /// Wraps long lines at the width of their panes in every session window, or lets them run on.
  @objc func toggleLineWrapping(_ sender: Any?) {
    lineWrapping.isOn.toggle()
  }

  /// Wraps lines as the user last chose, in whichever window.
  func observeLineWrapping() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(lineWrappingDidChange(_:)),
      name: LineWrapping.didChangeNotification, object: lineWrapping.defaults)
  }

  @objc private func lineWrappingDidChange(_ notification: Notification) {
    presentation.keepingTheLineOfBInPlace {
      presentation.wrapsLines = lineWrapping.isOn
      layout.view.layoutSubtreeIfNeeded()
    }
    updateFooter()
  }

  /// Shows every line of every pane.
  @objc func showAllLines(_ sender: Any?) {
    presentation.showAllRows()
  }

  /// Collapses long runs of unchanged lines again, except where the result is worked on and the
  /// run of the insertion point.
  @objc func collapseUnchangedLines(_ sender: Any?) {
    presentation.collapseUnchangedRows(caretLine: caretLineInTextMode)
  }

  /// The line of the result that the insertion point is on in text mode, or `nil` in block
  /// mode.
  var caretLineInTextMode: Int? {
    guard isInTextMode, let result = layout.resultPane else { return nil }
    return result.content.row(atOffset: result.documentView.selectedRange().location)
  }

  /// Makes the text larger, by a step of the font sizes.
  @objc func zoomIn(_ sender: Any?) {
    fontSize = Self.fontSizes.first { $0 > fontSize } ?? fontSize
  }

  /// Makes the text smaller, by a step of the font sizes.
  @objc func zoomOut(_ sender: Any?) {
    fontSize = Self.fontSizes.last { $0 < fontSize } ?? fontSize
  }

  /// Shows the text at its standard size.
  @objc func actualSize(_ sender: Any?) {
    fontSize = Self.standardFontSize
  }

  /// Asks in a sheet for a line and jumps to it in the pane with the focus.
  @objc func goToLine(_ sender: Any?) {
    guard let window else { return }
    let field = NSTextField(string: "")
    field.placeholderString = String(
      localized: "Line Number", bundle: .module, comment: "Placeholder of the field of Go to Line.")
    field.frame.size.width = WindowMetrics.lineFieldWidth
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Go to Line", bundle: .module, comment: "Title of the sheet of Go to Line.")
    alert.accessoryView = field
    alert.addButton(
      withTitle: String(localized: "Go", bundle: .module, comment: "Button: jump to the line."))
    alert.addButton(
      withTitle: String(
        localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing."))
    alert.window.initialFirstResponder = field
    let pane = focusedPane
    alert.beginSheetModal(for: window) { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .alertFirstButtonReturn, let line = Int(field.stringValue) else { return }
        self?.go(toLine: line, in: pane)
      }
    }
  }

  /// Opens the file that the result is written to in the app the system has for its type.
  @objc func openInEditor(_ sender: Any?) {
    guard let url = editableFileURL else { return }
    if !workspace.open(url) {
      Self.logger.error("The workspace did not open \(url.path(percentEncoded: false))")
    }
  }

  /// Jumps to `line`, counted from 1 as the gutter shows it, in `pane`, and puts the insertion
  /// point at its start if the pane is the result and has the focus.
  func go(toLine line: Int, in pane: PaneView) {
    let row = presentation.go(toLine: line - 1, in: pane)
    if pane === layout.resultPane && isInTextMode {
      let textView = pane.documentView
      textView.setSelectedRange(NSRange(location: pane.content.offset(ofRow: row), length: 0))
    }
  }

  /// The real file behind the window, which Open in Editor opens, if it exists on disk: the file
  /// the result of a merge is written to, or the side of a comparison that is the working copy.
  var editableFileURL: URL? {
    guard let url = context.resultURL ?? workingCopyURL,
      FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    else { return nil }
    return url
  }

  /// The file of the side of a comparison that `git difftool` names the working copy.
  private var workingCopyURL: URL? {
    guard let difftool = context.difftool else { return nil }
    let sides: [(Role, DiffSideRole)] = [(.b, difftool.rightRole), (.a, difftool.leftRole)]
    let role = sides.first { $0.1 == .workingCopy }?.0
    return role.flatMap { presentation.changes.session.file(for: $0)?.url }
  }

  /// Lets the window get no smaller than the panes in view need.
  func updateMinimumSize() {
    layout.updateMinimumWidths()
    window?.contentMinSize = minimumContentSize
  }

  /// The least size of the content of the window: what the panes in view and the footer need,
  /// and no narrower than the toolbar needs to keep its count and arrows in view.
  var minimumContentSize: CGSize {
    let footerWidth = content.showsFooter ? content.footer.minimumWidth : 0
    return CGSize(
      width: max(layout.minimumWidth, WindowMetrics.minimumToolbarWidth, footerWidth),
      height: layout.minimumHeight + content.footerHeightInView)
  }

  /// The size of the code at Actual Size.
  static let standardFontSize = Theme().font.pointSize

  /// The sizes of the code that Zoom In and Zoom Out step through.
  static let fontSizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32]
}

extension PaneContent {
  /// The row that the UTF-16 `offset` of the text lies in.
  func row(atOffset offset: Int) -> Int {
    var row = 0
    for unit in text.utf16.prefix(offset) where unit == UInt16(UInt8(ascii: "\n")) {
      row += 1
    }
    return row
  }
}
