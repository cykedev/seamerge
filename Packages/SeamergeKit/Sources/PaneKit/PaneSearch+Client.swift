import AppKit

/// The search as the finder sees it: the searchable pieces of the panes' lines as one string, the
/// selection of one pane, and the panes that show the matches.
///
/// The finder addresses the text by offsets into the search text, which the search translates
/// into a pane and a range of its text.
extension PaneSearch: @MainActor NSTextFinderClient {
  /// Matches can be selected in the panes.
  public var isSelectable: Bool { true }

  /// One selection in one pane: the finder cannot select matches in several panes at once.
  public var allowsMultipleSelection: Bool { false }

  /// Whether the search is limited to one pane that can be edited, the only way to replace.
  public var isEditable: Bool { editablePane != nil }

  /// The part of the search text that holds `characterIndex`: lines of one pane, which always
  /// end with a search boundary.
  ///
  /// The finder asks from a thread of its own while it searches as the user types, so this reads
  /// the copy of the text that the search took last, which never changes; the search replaces
  /// it as a whole.
  public nonisolated func string(
    at characterIndex: Int, effectiveRange outRange: NSRangePointer,
    endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>
  ) -> String {
    outFlag.pointee = true
    let (range, string) = snapshot.withLock { text -> (Range<Int>, String) in
      guard let index = text.partIndex(containing: characterIndex) else {
        return (text.length..<text.length, "")
      }
      return (text.parts[index].range, text.text(ofPart: index))
    }
    outRange.pointee = NSRange(range)
    return string
  }

  /// The length of the search text.
  ///
  /// The finder asks on the main thread before it searches, which is when the search takes the
  /// text anew after a change; from any other thread, the length of the copy taken last.
  public nonisolated func stringLength() -> Int {
    guard Thread.isMainThread else { return snapshot.withLock(\.length) }
    return MainActor.assumeIsolated { searchText().length }
  }

  /// The selection of the pane that Find Next starts from, in the search text: within the piece
  /// of its line, or empty at the next piece if it starts where the search does not go.
  public var firstSelectedRange: NSRange {
    let text = searchText()
    guard let pane = selectionPane, let index = panes.firstIndex(where: { $0 === pane }),
      let selection = Range(pane.textView.selectedRange()),
      let range = text.searchRange(ofPaneRange: selection, inPane: index)
    else { return NSRange(location: 0, length: 0) }
    return NSRange(range)
  }

  /// The selection that Find Next starts from; setting it selects the match in its pane.
  ///
  /// During a find command from the menu, the focus moves to the pane of the match if it was in
  /// another pane of the search. Otherwise it stays where it is: in the find bar, as in the find
  /// bar of a text view, or where the user just put it, when the finder selects its current
  /// match as the find bar loses the focus.
  ///
  /// A match that reaches from one line into the next, as for a search for a line break, is no
  /// match in a pane: the selection goes to its end, where Find Next goes on.
  public var selectedRanges: [NSValue] {
    get { [NSValue(range: firstSelectedRange)] }
    set {
      guard let first = newValue.first.flatMap({ Range($0.rangeValue) }) else { return }
      let text = searchText()
      guard
        let place = text.paneRange(of: first)
          ?? text.paneRange(of: first.upperBound..<first.upperBound)
      else { return }
      let pane = panes[place.pane]
      let movesFocus = isPerformingAction && (focusedPane.map { $0 !== pane } ?? false)
      pane.textView.setSelectedRange(NSRange(place.range))
      if movesFocus {
        pane.window?.makeFirstResponder(pane.textView)
      }
      currentPane = pane
    }
  }

  /// Brings a match into view in its pane and selects it there, expanding a collapsed run
  /// around it through the pane's delegate, and tells the search's delegate.
  ///
  /// The finder calls this for the current match, after Find Next, Find Previous or a search as
  /// the user types. Besides the outline that every match has and the find indicator, which
  /// fades, the selection marks the current match for as long as it stays there.
  public func scrollRangeToVisible(_ range: NSRange) {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched) else {
      return
    }
    let pane = panes[place.pane]
    pane.textView.reveal(offset: place.range.lowerBound)
    pane.textView.setSelectedRange(NSRange(place.range))
    currentPane = pane
    delegate?.paneSearch(self, didReveal: Match(pane: pane, range: place.range))
  }

  /// The text view of the pane that shows the character at `index`, with the longest range of
  /// the search text around it that the pane shows.
  public func contentView(
    at index: Int, effectiveCharacterRange outRange: NSRangePointer
  ) -> NSView {
    guard let stretch = searchText().paneStretch(containing: index) else {
      outRange.pointee = NSRange(location: index, length: 0)
      return findBar
    }
    outRange.pointee = NSRange(stretch.range)
    return panes[stretch.pane].textView
  }

  /// The rectangles of `range` of the search text in the text view of its pane, where the
  /// finder shows its indicator.
  public func rects(forCharacterRange range: NSRange) -> [NSValue]? {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched) else {
      return nil
    }
    return panes[place.pane].textView.rects(ofFoundRange: place.range).map { NSValue(rect: $0) }
  }

  /// The parts of the search text that the panes show now.
  public var visibleCharacterRanges: [NSValue] {
    let text = searchText()
    return panes.indices.flatMap { index in
      text.searchRanges(within: panes[index].textView.visibleTextRange, ofPane: index)
    }
    .sorted { $0.lowerBound < $1.lowerBound }
    .map { NSValue(range: NSRange($0)) }
  }

  /// Draws the characters of `range` of the search text as the find indicator shows them.
  public func drawCharacters(in range: NSRange, forContentView view: NSView) {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched),
      panes[place.pane].textView === view
    else { return }
    panes[place.pane].textView.drawFoundCharacters(in: place.range)
  }

  /// Begins a replacement of the matches at `ranges` in the editable pane, as one step of undo;
  /// refuses it while the search is not limited to such a pane.
  public func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
    guard let pane = editablePane else { return false }
    let text = searchText()
    let paneIndex = panes.firstIndex { $0 === pane }
    guard
      ranges.allSatisfy({ value in
        Range(value.rangeValue).flatMap(text.paneRange(of:)).map { $0.pane == paneIndex } ?? false
      })
    else { return false }
    // The text view keeps no undo of its own and answers none; the window has the undo of the pane.
    let undoManager = pane.undoManager
    undoManager?.beginUndoGrouping()
    // Replace All of one match is still Replace All; the find bar itself replaces one at a time.
    let replacesAll =
      ranges.count > 1 || actionUnderWay == .replaceAll || actionUnderWay == .replaceAllInSelection
    replacement = (undoManager, replacesAll)
    return true
  }

  /// Replaces `range` of the search text by `string` the way typing would: the editing delegate
  /// of the pane decides how.
  ///
  /// The finder replaces from the last match to the first, so the ranges refer to the text that
  /// the replacement began in, which the search keeps until the replacement is over.
  public func replaceCharacters(in range: NSRange, with string: String) {
    guard let pane = editablePane, let searched = Range(range),
      let place = searchText().paneRange(of: searched), panes[place.pane] === pane
    else { return }
    pane.textView.replaceFoundText(PaneEdit(range: place.range, text: string))
  }

  /// Ends the replacement: its edits become one step of undo, named after it.
  public func didReplaceCharacters() {
    guard let (undoManager, replacesAll) = replacement else { return }
    replacement = nil
    if let undoManager {
      undoManager.setActionName(
        replacesAll
          ? String(localized: "Replace All", bundle: .module)
          : String(localized: "Replace", bundle: .module))
      undoManager.endUndoGrouping()
    }
  }
}
