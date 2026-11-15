import AppKit
import PaneKit

/// Block mode and text mode, which follow the focus: in block mode the focus is in a pane above
/// the result, and single keys are commands; in text mode the insertion point is in the result,
/// and keys type.
extension SessionWindowController: SessionKeyHandling {
  /// Carries out the single keys of block mode and leaves text mode with Escape; every other
  /// key goes to the view with the focus.
  ///
  /// In block mode, a key without Command or Control that is no command does nothing, so that it
  /// neither types nor beeps; only the page keys scroll as they do elsewhere. Return resolves the
  /// current block by hand, which moves into text mode, and moves into text mode where there is
  /// no block to resolve; Escape leaves text mode.
  func handleKeyDown(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.function, .numericPad, .capsLock])
    let key = event.charactersIgnoringModifiers ?? ""
    // A toggle with the focus, under Keyboard Navigation, takes Space and the side arrows, as a
    // segmented control does.
    if window?.firstResponder is NSControl, modifiers.isEmpty,
      [" ", SessionCommand.leftArrow, SessionCommand.rightArrow].contains(key)
    {
      return false
    }
    if isInTextMode {
      guard key == Self.escape, modifiers.isEmpty,
        layout.resultPane?.documentView.hasMarkedText() == false
      else { return false }
      leaveTextMode()
      return true
    }
    guard isInBlockMode, modifiers.isDisjoint(with: [.command, .control]) else { return false }
    if let command = SessionCommand(blockModeKey: Keystroke(key, modifiers)) {
      if command == .resolveManually && !canPerform(command) {
        enterTextMode()
      } else {
        perform(command)
      }
    } else if Self.pageKeys.contains(key) {
      return false
    }
    return true
  }

  /// Moves the focus to the next pane.
  @objc func selectNextPane(_ sender: Any?) {
    focusPane(offset: 1)
  }

  /// Moves the focus to the previous pane.
  @objc func selectPreviousPane(_ sender: Any?) {
    focusPane(offset: -1)
  }

  /// Whether the focus is in a pane above the result that is in view, or in the result beside
  /// its text, as after a click on a toggle.
  ///
  /// Text the user types into beside the text of the result, such as the field of its find bar,
  /// takes every key, as a field does anywhere.
  var isInBlockMode: Bool {
    let isInSource = layout.sourcePanes.contains {
      $0.pane.isShown && window?.firstResponder === $0.pane.documentView
    }
    let isBesideResult =
      layout.resultPane.map { $0.isShown && $0.holdsFocus } == true && !isInTextMode
      && !(window?.firstResponder is NSText)
    return isInSource || isBesideResult
  }

  /// Whether the focus is in the text of the result.
  var isInTextMode: Bool {
    guard let resultPane = layout.resultPane else { return false }
    return window?.firstResponder === resultPane.documentView
  }

  /// The panes in view, in the order the focus moves through them: A, Base, B, the result.
  var focusablePanes: [PaneView] {
    presentation.allPanes.filter(\.isShown)
  }

  /// Carries out `command`, as its menu item does, if it can have an effect now.
  func perform(_ command: SessionCommand) {
    guard canPerform(command) else { return }
    NSApplication.shared.sendAction(command.action, to: self, from: nil)
  }

  /// Moves the focus into the result, with the insertion point at the start of the current
  /// block; a comparison, which has no result, stays in block mode.
  func enterTextMode() {
    guard let result = layout.resultPane, result.isShown, let window else { return }
    window.makeFirstResponder(result.documentView)
    placeInsertionPointAtCurrentBlock()
  }

  /// Moves the focus back to the pane above the result that had it last.
  func leaveTextMode() {
    let sources = layout.sourcePanes.map(\.pane).filter(\.isShown)
    guard let pane = sources.first(where: { $0 === lastSourcePane }) ?? sources.first else {
      return
    }
    window?.makeFirstResponder(pane.documentView)
  }

  /// Moves the focus `offset` panes on from the pane that has it, around the ends; the result
  /// keeps its insertion point and selection.
  ///
  /// Under Keyboard Navigation, the focus reaches the result at the toggles of its current block,
  /// in block mode; Return then moves into its text.
  private func focusPane(offset: Int) {
    let panes = focusablePanes
    guard !panes.isEmpty, let window else { return }
    let current = panes.firstIndex(where: \.holdsFocus)
    let pane = panes[current.map { ($0 + offset + panes.count) % panes.count } ?? 0]
    if pane === layout.resultPane, displayOptions.navigatesWithKeyboard,
      let block = presentation.currentBlock,
      presentation.decisionColumn?.focusToggles(ofBlock: block) == true
    {
      return
    }
    window.makeFirstResponder(pane.documentView)
  }

  /// Puts the insertion point at the first row of the current block in the result, and brings
  /// it into view as far as needed, as the text view does for its own insertion point.
  private func placeInsertionPointAtCurrentBlock() {
    guard let result = layout.resultPane, let block = presentation.currentBlock else { return }
    let offset = result.content.offset(ofRow: result.content.blocks[block].rows.lowerBound)
    let textView = result.documentView
    textView.setSelectedRange(NSRange(location: offset, length: 0))
    textView.scrollRangeToVisible(textView.selectedRange())
  }

  private static let escape = "\u{1B}"
  private static let pageKeys: Set<String> = ["\u{F72C}", "\u{F72D}"]
}

extension PaneContent {
  /// The UTF-16 offset where `row` starts in the text, or the length of the text past its last
  /// row.
  func offset(ofRow row: Int) -> Int {
    var offset = 0
    var currentRow = 0
    for unit in text.utf16 {
      if currentRow == row { return offset }
      offset += 1
      if unit == UInt16(UInt8(ascii: "\n")) {
        currentRow += 1
      }
    }
    return offset
  }
}
