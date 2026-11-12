import AppKit
import MergeModel
import PaneKit

extension SessionWindowController {
  /// The context menu for `hit` in `pane`: jumps first, then text commands, each only where it
  /// has an effect, except that Cut, Copy and Paste stay and are disabled where they have none.
  ///
  /// The menu holds no key equivalents, and none of the text view's standard commands.
  func contextMenu(for hit: PaneHit, in pane: PaneView) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for command in SessionCommand.contextMenuJumps(onChangedBlock: hit.block != nil)
    where canPerform(command) {
      menu.addItem(item(command.title, action: command.action, target: self))
    }
    if !menu.items.isEmpty {
      menu.addItem(.separator())
    }
    let textView = pane.documentView
    let isResult = pane === layout.resultPane
    if isResult {
      menu.addItem(textItem(Self.cutTitle, action: #selector(NSText.cut(_:)), in: textView))
    }
    menu.addItem(copyItem(at: CopiedPlace(pane: pane, block: hit.block)))
    if isResult {
      menu.addItem(textItem(Self.pasteTitle, action: #selector(NSText.paste(_:)), in: textView))
    }
    if hit.block == nil {
      menu.addItem(
        textItem(Self.selectAllTitle, action: #selector(NSText.selectAll(_:)), in: textView))
    }
    return menu
  }

  /// The context menu of the header of the pane of `role`, or of the result for `nil`: copying
  /// the path of its file and showing the file in the Finder, or `nil` if it has no file.
  func headerMenu(for role: Role?) -> NSMenu? {
    guard let url = fileURL(of: role) else { return nil }
    let menu = NSMenu()
    menu.autoenablesItems = false
    let copyPath = item(Self.copyPathTitle, action: #selector(copyPath(_:)), target: self)
    copyPath.representedObject = url
    menu.addItem(copyPath)
    if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      let show = item(Self.showInFinderTitle, action: #selector(showInFinder(_:)), target: self)
      show.representedObject = url
      menu.addItem(show)
    }
    return menu
  }

  /// Copies the lines of a block: of the block at the place of a context menu that sends it, or
  /// else of the current block in the pane with the focus.
  @objc func copyBlock(_ sender: Any?) {
    let place =
      (sender as? NSMenuItem)?.representedObject as? CopiedPlace
      ?? CopiedPlace(pane: focusedPane, block: presentation.currentBlock)
    let text = blockText(at: place)
    guard !text.isEmpty else { return }
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// The Copy of a context menu at `place`: the standard Copy of the selection if text is
  /// selected in its pane, or else Copy Block for the block there, under the same name.
  private func copyItem(at place: CopiedPlace) -> NSMenuItem {
    guard !hasSelection(place.pane) else {
      return textItem(
        Self.copyTitle, action: #selector(NSText.copy(_:)), in: place.pane.documentView)
    }
    let copy = item(Self.copyTitle, action: SessionCommand.copyBlock.action, target: self)
    copy.representedObject = place
    copy.isEnabled = !blockText(at: place).isEmpty
    return copy
  }

  /// Copies the path of the file of the sender.
  @objc func copyPath(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    pasteboard.clearContents()
    pasteboard.setString(url.path(percentEncoded: false), forType: .string)
  }

  /// Shows the file of the sender in the Finder.
  @objc func showInFinder(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    workspace.activateFileViewerSelecting([url])
  }

  /// The pane that Copy Block and Go to Line act in: the one with the focus, or else the pane
  /// above the result that had it last.
  var focusedPane: PaneView {
    presentation.allPanes.first { window?.firstResponder === $0.documentView }
      ?? lastSourcePane ?? layout.sourcePanes[0].pane
  }

  /// Whether text is selected in `pane`.
  private func hasSelection(_ pane: PaneView) -> Bool {
    pane.documentView.selectedRanges.contains { $0.rangeValue.length > 0 }
  }

  /// The text of the block at `place`, which Copy copies where nothing is selected: in the
  /// result the text of the block as the result has it, in a source its lines; empty if `place`
  /// is on no block or the block has no text, as an open conflict in the result has none.
  func blockText(at place: CopiedPlace) -> String {
    guard let block = place.block else { return "" }
    if place.pane === layout.resultPane, let result = presentation.result {
      let changedBlock = presentation.changes.blocks[block]
      // An open conflict shows a preview of the sides, which is no text of the result.
      guard result.document.segment(for: changedBlock).state != .open else { return "" }
      let range = result.document.range(of: changedBlock)
      let text = result.text.utf16
      let start = text.index(text.startIndex, offsetBy: range.lowerBound)
      let end = text.index(start, offsetBy: range.count)
      return String(result.text[start..<end])
    }
    return place.pane.content.text(ofLinesIn: place.pane.content.blocks[block].rows)
  }

  /// The file behind the pane of `role`, or behind the result for `nil`.
  private func fileURL(of role: Role?) -> URL? {
    guard let role else { return context.resultURL }
    return presentation.changes.session.file(for: role)?.url
  }

  private func item(_ title: String, action: Selector, target: AnyObject) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target
    return item
  }

  /// An item that sends `action` to `textView`, enabled as the text view decides.
  private func textItem(_ title: String, action: Selector, in textView: NSTextView) -> NSMenuItem {
    let item = item(title, action: action, target: textView)
    item.isEnabled = textView.validateUserInterfaceItem(item)
    return item
  }

  private static let cutTitle = String(
    localized: "Cut", bundle: .module, comment: "Context menu: cut the selected text.")
  private static let copyTitle = String(
    localized: "Copy", bundle: .module,
    comment: "Context menu: copy the selected text, or the block if nothing is selected.")
  private static let pasteTitle = String(
    localized: "Paste", bundle: .module, comment: "Context menu: paste text.")
  private static let selectAllTitle = String(
    localized: "Select All", bundle: .module, comment: "Context menu: select the whole text.")
  private static let copyPathTitle = String(
    localized: "Copy Path", bundle: .module, comment: "Context menu of a header.")
  private static let showInFinderTitle = String(
    localized: "Show in Finder", bundle: .module, comment: "Context menu of a header.")
}

/// Where a context menu was opened, for its Copy command: the pane, and the block under the
/// pointer, if any.
final class CopiedPlace: NSObject {
  let pane: PaneView
  let block: Int?

  init(pane: PaneView, block: Int?) {
    self.pane = pane
    self.block = block
  }
}

extension PaneContent {
  /// The lines of `rows`, without the filler rows, each with a line feed.
  func text(ofLinesIn rows: Range<Int>) -> String {
    var lines: [Substring] = []
    var row = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      defer { row += 1 }
      guard row < rows.upperBound else { break }
      if rows.contains(row) && lineNumbers[row] >= 0 {
        lines.append(line)
      }
    }
    return lines.map { $0 + "\n" }.joined()
  }
}
