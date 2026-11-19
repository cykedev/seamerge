package import AppKit
import Synchronization

/// The search as the finder sees it: the searchable pieces of the panes' lines as one string, the
/// selection of one pane, and the panes that show the matches.
///
/// The finder addresses the text by offsets into the search text, which the search translates
/// into a pane and a range of its text.
extension PaneSearch: @MainActor NSTextFinderClient {
  /// Matches can be selected in the panes.
  package var isSelectable: Bool { true }

  /// One selection in one pane: the finder cannot select matches in several panes at once.
  package var allowsMultipleSelection: Bool { false }

  /// Whether text can be replaced: in the pane that the search is limited to, or in the
  /// replaceable pane, which the field for replacing limits the search to as it comes.
  package var isEditable: Bool {
    editablePane != nil || replaceablePane?.editingDelegate != nil
  }

  /// The search text, as one string that never changes, which the finder reads on threads of its
  /// own while it searches as the user types, often on two at once; handed to it in parts, the
  /// text made two searches at once crash.
  ///
  /// A line feed stands between every two pieces of the text, so that no match of a text
  /// without one reaches from one line, section or pane into the next. The finder asks on the
  /// main thread before it searches, which is when the search takes the text anew after a
  /// change; from any other thread, it gets the copy taken last.
  package nonisolated var string: String {
    guard Thread.isMainThread else { return snapshot.withLock(\.string) }
    return MainActor.assumeIsolated { searchText().string }
  }

  /// The selection of the pane that Find Next starts from, in the search text: within the piece
  /// of its line, or empty at the next piece if it starts where the search does not go.
  package var firstSelectedRange: NSRange {
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
  package var selectedRanges: [NSValue] {
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
  package func scrollRangeToVisible(_ range: NSRange) {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched) else {
      return
    }
    let pane = panes[place.pane]
    pane.textView.reveal(offset: place.range.lowerBound)
    pane.textView.setSelectedRange(NSRange(place.range))
    currentPane = pane
    delegate?.paneSearch(
      self,
      didReveal: Match(
        pane: pane, range: place.range, row: pane.row(containingOffset: place.range.lowerBound)))
  }

  /// The text view of the pane that shows the character at `index`, with the longest range of
  /// the search text around it that the pane shows.
  package func contentView(
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
  package func rects(forCharacterRange range: NSRange) -> [NSValue]? {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched) else {
      return nil
    }
    return panes[place.pane].textView.rects(ofFoundRange: place.range).map { NSValue(rect: $0) }
  }

  /// The parts of the search text that the panes show now.
  package var visibleCharacterRanges: [NSValue] {
    let text = searchText()
    return panes.indices.flatMap { index in
      text.searchRanges(within: panes[index].textView.visibleTextRange, ofPane: index)
    }
    .sorted { $0.lowerBound < $1.lowerBound }
    .map { NSValue(range: NSRange($0)) }
  }

  /// Draws the characters of `range` of the search text as the find indicator shows them.
  package func drawCharacters(in range: NSRange, forContentView view: NSView) {
    guard let searched = Range(range), let place = searchText().paneRange(of: searched),
      panes[place.pane].textView === view
    else { return }
    panes[place.pane].textView.drawFoundCharacters(in: place.range)
  }

  /// Begins a replacement of the matches at `ranges` in the editable pane, as one step of undo;
  /// refuses it while the search is not limited to such a pane.
  ///
  /// A match that reaches from one line into the next belongs to no pane and stays as it is;
  /// the others are replaced.
  package func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
    guard let pane = editablePane else { return false }
    let text = searchText()
    let paneIndex = panes.firstIndex { $0 === pane }
    let places = ranges.compactMap { Range($0.rangeValue).flatMap(text.paneRange(of:)) }
    guard !places.isEmpty, places.allSatisfy({ $0.pane == paneIndex }) else { return false }
    // The text view keeps no undo of its own and answers none; the window has the undo of the pane.
    let undoManager = pane.undoManager
    undoManager?.beginUndoGrouping()
    // Replace All of one match is still Replace All; the find bar itself replaces one at a time.
    let replacesAll =
      ranges.count > 1 || actionUnderWay == .replaceAll || actionUnderWay == .replaceAllInSelection
    replacement = (undoManager, replacesAll)
    delegate?.paneSearchWillReplace(self)
    return true
  }

  /// Replaces `range` of the search text by `string` the way typing would: the editing delegate
  /// of the pane decides how.
  ///
  /// The finder replaces from the last match to the first, so the ranges refer to the text that
  /// the replacement began in, which the search keeps until the replacement is over.
  package func replaceCharacters(in range: NSRange, with string: String) {
    guard let pane = editablePane, let searched = Range(range),
      let place = searchText().paneRange(of: searched), panes[place.pane] === pane
    else { return }
    pane.textView.replaceFoundText(PaneEdit(range: place.range, text: string))
  }

  /// Ends the replacement: its edits become one step of undo, named after it.
  package func didReplaceCharacters() {
    guard let (undoManager, replacesAll) = replacement else { return }
    replacement = nil
    // Replace All leaves no match of the search; the finder searches again only as the search
    // text changes.
    if replacesAll {
      hasFoundMatches = false
    }
    delegate?.paneSearch(self, didReplaceAll: replacesAll)
    if let undoManager {
      undoManager.setActionName(Self.undoActionName(replacingAll: replacesAll))
      undoManager.endUndoGrouping()
    }
  }

  /// The name of the step of undo that replacing makes: Replace All for all matches, also if
  /// there is only one, else Replace.
  package static func undoActionName(replacingAll replacesAll: Bool) -> String {
    replacesAll
      ? String(localized: "Replace All", bundle: .module)
      : String(localized: "Replace", bundle: .module)
  }
}
