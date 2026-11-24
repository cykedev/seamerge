import AppKit
import MergeModel
import PaneKit

extension SessionWindowController {
  /// The context menu for `hit` in `pane`, in up to three groups: deciding or copying the block
  /// under the pointer, resetting and jumping, and the text commands.
  ///
  /// Each entry stands only where it has an effect, except that Cut, Copy and Paste stay and are
  /// disabled where they have none. The menu holds no key equivalents, and none of the text
  /// view's standard commands; every entry carries out a command of the main menu.
  func contextMenu(for hit: PaneHit, in pane: PaneView) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    // An editable text view would get the services and the writing tools of the system added.
    menu.allowsContextMenuPlugIns = false
    menu.automaticallyInsertsWritingToolsItems = false
    let isResult = pane === layout.resultPane
    var groups: [[NSMenuItem]] = []
    if hit.block != nil {
      if isResult {
        groups.append(resultDecisionItems())
      } else {
        // The single column offers the copies as well, without decisions of its own.
        let role = layout.sourcePanes.first { $0.pane === pane }?.role
        groups.append((role.map(sourceDecisionItems(for:)) ?? []) + copyItems())
      }
    }
    // On a changed block, resetting it comes first; on unchanged text, the jump to the next
    // conflict, as the most frequent.
    let isOnBlock = hit.block != nil
    let resets = resetItems(onChangedBlock: isOnBlock)
    let jumps = jumpItems(onChangedBlock: isOnBlock)
    groups.append(isOnBlock ? resets + jumps : jumps + resets)
    groups.append(textItems(for: hit, in: pane, isResult: isResult))
    for group in groups where !group.isEmpty {
      if !menu.items.isEmpty {
        menu.addItem(.separator())
      }
      for item in group {
        menu.addItem(item)
      }
    }
    return menu
  }

  /// The decisions that the pane of `role` offers for the current block: taking its version,
  /// adding it to the sources already taken, and taking nothing.
  private func sourceDecisionItems(for role: Role) -> [NSMenuItem] {
    let name = presentation.headers[role]?.distinctName ?? role.letter
    var items: [NSMenuItem] = []
    if canPerform(.use(role)) {
      items.append(
        item(
          String(
            localized: "Use Version of \(name)", bundle: .module,
            comment: "Context menu of a changed block of a side, such as Use Version of main."),
          action: SessionCommand.use(role).action, target: self))
    }
    let takesOthers = currentResultBlock.map { block in
      presentation.result?.document.segment(for: block).sources.isEmpty == false
        && presentation.result?.document.segment(for: block).state != .open
    }
    if takesOthers == true && !isSourceOn(role) && canPerform(.toggle(role)) {
      items.append(
        item(
          String(
            localized: "Also Use \(name)", bundle: .module,
            comment: "Context menu of a changed block of a side: add its lines after those taken."),
          action: SessionCommand.toggle(role).action, target: self))
    }
    if canPerform(.useNone) {
      items.append(
        item(SessionCommand.useNone.title, action: SessionCommand.useNone.action, target: self))
    }
    return items
  }

  /// The copies of the current block of a comparison that have an effect, each named after the
  /// file it copies to, such as Copy to main.swift.
  private func copyItems() -> [NSMenuItem] {
    [PaneSeam.CopyDirection.toRight, .toLeft].filter { canPerform(.copy($0)) }.map { direction in
      item(
        String(
          localized: "Copy to \(copyTargetName(direction))", bundle: .module,
          comment:
            "Context menu of a changed block of a comparison: copy it to the named file, such as Copy to main.swift."
        ),
        action: SessionCommand.copy(direction).action, target: self)
    }
  }

  /// The decisions that the result offers for the current block: the commands of the Merge menu
  /// that choose its sources, each with an effect of its own, with a checkmark at the one whose
  /// outcome the block holds; then resolving it by hand.
  ///
  /// A command with no effect stands only while it carries the checkmark, so that the menu shows
  /// what the block takes and in which order.
  private func resultDecisionItems() -> [NSMenuItem] {
    let current = currentChoice
    var items: [NSMenuItem] = []
    for command in distinctChoices where command == current || canPerform(command) {
      let choice = item(command.title, action: command.action, target: self)
      choice.state = command == current ? .on : .off
      items.append(choice)
    }
    if canPerform(.resolveManually) {
      items.append(
        item(
          SessionCommand.resolveManually.title, action: SessionCommand.resolveManually.action,
          target: self))
    }
    return items
  }

  /// The commands that reset decisions, as far as each has an effect: on a changed block in a
  /// submenu Reset, or as Reset Change alone if only the block can be reset; on unchanged text
  /// the two that reset throughout the window.
  private func resetItems(onChangedBlock: Bool) -> [NSMenuItem] {
    let windowWide = [SessionCommand.reopenAllConflicts, .resetAllDecisions].filter(canPerform)
    guard onChangedBlock else {
      return windowWide.map { item($0.title, action: $0.action, target: self) }
    }
    let commands = [SessionCommand.resetChange].filter(canPerform) + windowWide
    if commands == [.resetChange] {
      return [
        item(
          String(
            localized: "Reset Change", bundle: .module,
            comment: "Context menu: return the block to how it was loaded."),
          action: SessionCommand.resetChange.action, target: self)
      ]
    }
    guard !commands.isEmpty else { return [] }
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    for command in commands {
      submenu.addItem(item(command.title, action: command.action, target: self))
    }
    let reset = NSMenuItem(
      title: String(
        localized: "Reset", bundle: .module,
        comment:
          "Resetting decisions: the button of the sheet before resetting every one, and the submenu of a context menu with the ways to reset."
      ),
      action: nil, keyEquivalent: "")
    reset.submenu = submenu
    return [reset]
  }

  /// The jumps that have an effect from the block under the pointer, or from unchanged text.
  private func jumpItems(onChangedBlock: Bool) -> [NSMenuItem] {
    SessionCommand.contextMenuJumps(onChangedBlock: onChangedBlock).filter(canPerform).map {
      item($0.title, action: $0.action, target: self)
    }
  }

  /// The text commands at `hit` in `pane`: Cut and Paste in the result, Copy, and Select All on
  /// unchanged text.
  private func textItems(for hit: PaneHit, in pane: PaneView, isResult: Bool) -> [NSMenuItem] {
    let textView = pane.documentView
    var items: [NSMenuItem] = []
    if isResult {
      items.append(textItem(Self.cutTitle, action: #selector(NSText.cut(_:)), in: textView))
    }
    items.append(copyItem(at: CopiedPlace(pane: pane, block: hit.block)))
    if isResult {
      items.append(textItem(Self.pasteTitle, action: #selector(NSText.paste(_:)), in: textView))
    }
    if hit.block == nil {
      items.append(
        textItem(Self.selectAllTitle, action: #selector(NSText.selectAll(_:)), in: textView))
    }
    return items
  }

  /// The context menu of the header of the pane of `role`, or of the result for `nil`: copying
  /// the path of its file and showing the file in the Finder, or `nil` if it has no file, as a
  /// side of text pasted from the clipboard has none of its own.
  func headerMenu(for role: Role?) -> NSMenu? {
    guard let url = fileURL(of: role), context.pastedTexts[url] == nil else { return nil }
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
  /// above the result that had it last, if it is in view, or the first pane in view.
  var focusedPane: PaneView {
    presentation.allPanes.first(where: \.holdsFocus)
      ?? lastSourcePane.flatMap { $0.isShown ? $0 : nil }
      ?? presentation.leadingPane ?? layout.sourcePanes[0].pane
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
    return presentation.changes.session.inputs[role]?.url
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
