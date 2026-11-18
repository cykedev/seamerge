import AppKit
import Synchronization

/// One find bar for several panes: the standard find bar of AppKit, searching the panes one
/// after the other in an order that the owner gives, and replacing in one editable pane.
///
/// The owner says which rows of which panes the search goes through, in reading order, with
/// ``sections``; PaneKit knows no blocks. A match never reaches across the end of a line or from
/// one pane into the next, and filler rows and previews are never searched. ``scope`` limits the
/// search to one pane, the only one that text can be replaced in; every replacement passes
/// through that pane's ``PaneView/editingDelegate`` as typing does, and Replace All is one step
/// of undo, which the delegate learns the start and end of.
///
/// Put ``findBar`` at the bottom of the window, below the panes. The search does not dim the
/// panes, whose tints carry meaning; it marks its matches in the panes and shows the current one
/// with the system's find indicator. A pane among the sections hands the find commands that reach
/// it to the search; a pane has no find bar of its own. The find bar reads the text while
/// it searches as the user types, on a thread of its own, from a copy that the search takes after
/// each change.
@MainActor
public final class PaneSearch: NSObject {
  /// Some rows of a pane that the search goes through.
  public struct Section {
    /// The pane.
    public var pane: PaneView

    /// The rows of the pane, on its grid.
    public var rows: Range<Int>

    /// Creates a section of `rows` of `pane`.
    public init(pane: PaneView, rows: Range<Int>) {
      self.pane = pane
      self.rows = rows
    }
  }

  /// A match of the search: a range of a pane's text, in UTF-16 code units.
  public struct Match {
    /// The pane whose text holds the match.
    public var pane: PaneView

    /// The range of the match in the text of the pane.
    public var range: Range<Int>

    /// The row of the pane that the match starts in.
    public var row: Int
  }

  /// The panes that the search goes through.
  public enum Scope {
    /// All the panes of the sections; nothing can be replaced.
    case allPanes

    /// The sections of one pane alone, which text can be replaced in if the pane is editable.
    case pane(PaneView)
  }

  /// The view that shows the find bar, which the owner puts at the bottom of the window.
  public let findBar = PaneFindBar()

  /// Learns which match the search shows and when the matches change; the search does not retain
  /// it.
  public weak var delegate: (any PaneSearchDelegate)?

  /// The rows that the search goes through, in the order that Find Next follows.
  ///
  /// Set the sections anew whenever the rows of a pane change their meaning, after an edit that
  /// adds or removes rows among them. Rows beyond the end of a pane are left out.
  public var sections: [Section] = [] {
    didSet { panesDidChange() }
  }

  /// The panes that the search goes through: all panes of the sections, or one of them alone.
  public var scope = Scope.allPanes {
    didSet { panesDidChange() }
  }

  /// The matches of the current search, in the order of the search, while the find bar shows
  /// them as the user types; empty while the find bar is closed.
  ///
  /// The search makes the list once it is asked for after the matches changed; ``matchCount``,
  /// ``panesWithMatches`` and ``matchRows(in:)`` tell about them without it.
  public var matches: [Match] {
    if let listedMatches {
      return listedMatches
    }
    let listed = found.places.map { Match(pane: panes[$0.pane], range: $0.range, row: $0.row) }
    listedMatches = listed
    return listed
  }

  /// The number of ``matches``.
  public var matchCount: Int { found.places.count }

  /// The panes that hold at least one of the ``matches``, in the order of the search.
  public private(set) var panesWithMatches: [PaneView] = []

  /// The rows of `pane` that the ``matches`` start in.
  public func matchRows(in pane: PaneView) -> IndexSet {
    guard let index = panes.firstIndex(where: { $0 === pane }),
      found.rowsByPane.indices.contains(index)
    else { return [] }
    return found.rowsByPane[index]
  }

  /// Whether the search as the user types found a match when it searched last, while the find
  /// bar is open.
  ///
  /// The matches go once the text changes, as after a replacement, and the finder does not
  /// search again until the search text changes; this still tells that the text was found.
  public internal(set) var hasFoundMatches = false

  /// Whether ``matches`` are what the finder found in the text as it is now: false once the text
  /// or the panes changed since it searched, and its matches are gone, until it searches again.
  public private(set) var matchesAreCurrent = false

  /// Whether the find bar shows the field for replacing, as the owner opened it or as the user
  /// switched it on or off in the bar.
  public private(set) var showsReplaceField = false

  /// The pane that text can be replaced in, if any and if it can be edited.
  ///
  /// The find bar offers its field for replacing while the pane is set; as the field comes, the
  /// search is limited to the pane, and as it goes, the search goes through all panes again,
  /// whether the owner or the user in the bar switched it.
  public var replaceablePane: PaneView?

  /// The finder that runs the find bar.
  private let finder = NSTextFinder()

  /// The text as the find bar reads it, which the search takes anew after a change once it is
  /// asked for.
  let snapshot = Mutex(SearchText.empty)

  /// The panes of the search in scope, in the order of their first section, by their index in
  /// the search text.
  private(set) var panes: [PaneView] = []

  /// Whether a pane's text or the sections changed since the search text was taken.
  private var isTextStale = true

  /// The pane of the match that the search showed last.
  var currentPane: PaneView?

  /// The find command under way, whose match takes the focus along to its pane, if any.
  private(set) var actionUnderWay: NSTextFinder.Action?

  /// Whether a find command is under way.
  var isPerformingAction: Bool { actionUnderWay != nil }

  /// A replacement that the finder has begun and not yet finished, with the undo manager that
  /// groups its edits and whether it replaces all matches.
  var replacement: (undoManager: UndoManager?, replacesAll: Bool)?

  /// The matches of the current search, placed in the panes of the search.
  private var found = FoundMatches.none

  /// The list of the matches, once it was asked for after they changed.
  private var listedMatches: [Match]?

  /// The matches that the finder found, made ready for the panes away from the main actor,
  /// while that is under way.
  private(set) var matchesInPreparation: Task<Void, Never>?

  /// Whether the finder found more matches while those under way were made ready.
  private var hasMatchesWaiting = false

  /// Observes the matches that the finder finds as the user types.
  private var matchObservation: NSKeyValueObservation?

  /// The panes whose text changes the search hears of.
  private var observedPanes: [PaneView] = []

  /// Creates a search without sections, with its find bar closed.
  public override init() {
    super.init()
    finder.client = self
    finder.findBarContainer = findBar
    finder.isIncrementalSearchingEnabled = true
    finder.incrementalSearchingShouldDimContentView = false
    findBar.search = self
    matchObservation = finder.observe(\.incrementalMatchRanges) { [weak self] _, _ in
      // The finder updates its matches on the main queue.
      MainActor.assumeIsolated { self?.matchesDidChange() }
    }
  }

  isolated deinit {
    close()
    for pane in observedPanes where pane.textView.search === self {
      pane.textView.search = nil
    }
  }

  /// Ends the search for good, as the window of the panes closes: takes the find indicator away
  /// and lets the finder go of the search.
  ///
  /// The find indicator updates after a delay, as the panes change their size, and holds the
  /// finder without retaining it; it must not find the finder gone.
  public func close() {
    finder.cancelFindIndicator()
    finder.client = nil
    finder.findBarContainer = nil
  }

  /// Carries out the find command of `sender`, a menu item or control whose tag is an
  /// `NSTextFinder.Action`, as the responder to `performTextFinderAction(_:)` does.
  public func performTextFinderAction(_ sender: Any?) {
    guard let action = Self.action(of: sender) else { return }
    perform(action)
  }

  /// Carries out `action` of the finder.
  public func perform(_ action: NSTextFinder.Action) {
    // The finder shows its bar in a scroll view of its own accord, but only hands it to any
    // other container, which is to show it; it hides it again itself. The bar shows before the
    // finder acts, so that its search field can take the focus.
    if action == .showFindInterface || action == .showReplaceInterface {
      findBar.isFindBarVisible = true
    }
    actionUnderWay = action
    defer { actionUnderWay = nil }
    finder.performAction(action)
  }

  /// Whether the find command of `item`, whose tag is an `NSTextFinder.Action`, can be carried
  /// out now.
  public func validate(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    guard let action = NSTextFinder.Action(rawValue: item.tag) else { return false }
    return validate(action)
  }

  /// Whether `action` of the finder can be carried out now.
  public func validate(_ action: NSTextFinder.Action) -> Bool {
    finder.validateAction(action)
  }

  /// The action of the finder that `sender` stands for, by its tag.
  private static func action(of sender: Any?) -> NSTextFinder.Action? {
    guard let tag = (sender as? any NSValidatedUserInterfaceItem)?.tag else { return nil }
    return NSTextFinder.Action(rawValue: tag)
  }

  /// The search text, taken anew if a pane's text or the sections changed since it was taken
  /// last, unless a replacement is under way, whose ranges refer to the text it began in.
  func searchText() -> SearchText {
    if isTextStale && replacement == nil {
      isTextStale = false
      let text = makeSearchText()
      snapshot.withLock { $0 = text }
      return text
    }
    return snapshot.withLock { $0 }
  }

  /// The pane of the search in scope that holds the focus, if any.
  var focusedPane: PaneView? {
    panes.first { $0.window?.firstResponder === $0.textView }
  }

  /// The pane whose selection Find Next starts from: the pane of the search that holds the
  /// focus, or else the pane of the last match shown, or else the first pane.
  var selectionPane: PaneView? {
    if let focusedPane { return focusedPane }
    if let currentPane, panes.contains(where: { $0 === currentPane }) { return currentPane }
    return panes.first
  }

  /// The pane that the search is limited to, if it can be edited: the only pane that text is
  /// replaced in.
  var editablePane: PaneView? {
    guard case .pane(let pane) = scope, pane.editingDelegate != nil else { return nil }
    return pane
  }

  /// Hands the focus to the pane whose selection the search starts from, after the find bar
  /// closed while it held the focus.
  func findBarDidCloseWithFocus() {
    guard let pane = selectionPane else { return }
    pane.window?.makeFirstResponder(pane.textView)
  }

  /// Clears the marks of the matches once the find bar closes, and lets go of the search text,
  /// a copy of all the text the search goes through, until the finder asks for it again.
  func findBarDidClose() {
    hasFoundMatches = false
    matchesAreCurrent = false
    showMatches(.none)
    guard replacement == nil else { return }
    // The finder keeps the text it read until it hears of a change.
    finder.noteClientStringWillChange()
    isTextStale = true
    snapshot.withLock { $0 = .empty }
  }

  /// Limits the search to the replaceable pane once the field for replacing comes, and searches
  /// all panes again once it goes, as the bar changes its height then.
  func findBarDidChangeHeight() {
    let shows = findBar.isFindBarVisible && findBar.showsReplaceField
    guard shows != showsReplaceField else { return }
    showsReplaceField = shows
    if shows, let replaceablePane {
      scope = .pane(replaceablePane)
    } else if !shows {
      scope = .allPanes
    }
  }

  private func makeSearchText() -> SearchText {
    let sections = sectionsInScope
    // The texts as the panes hold them, without a copy: the search text copies what it needs.
    let texts = panes.map { $0.textView.textStorage?.mutableString ?? NSMutableString() }
    let searched = sections.compactMap { section -> SearchText.Section? in
      guard let pane = panes.firstIndex(where: { $0 === section.pane }) else { return nil }
      let textView = section.pane.textView
      let grid = textView.grid
      let content = textView.content
      let text = texts[pane]
      let rows =
        min(
          section.rows.lowerBound, grid.rowCount)..<min(
          section.rows.upperBound, grid.rowCount)
      let lines = rows.compactMap { row -> Range<Int>? in
        guard !content.isFiller(row: row) else { return nil }
        let line = grid.offsets(ofRow: row)
        let endsWithLineFeed = !line.isEmpty && text.character(at: line.upperBound - 1) == 0x0A
        return line.lowerBound..<line.upperBound - (endsWithLineFeed ? 1 : 0)
      }
      return SearchText.Section(pane: pane, lines: lines, excluded: content.previews.map(\.range))
    }
    return SearchText(texts: texts, sections: searched)
  }

  private var sectionsInScope: [Section] {
    switch scope {
    case .allPanes: sections
    case .pane(let pane): sections.filter { $0.pane === pane }
    }
  }

  /// Takes over new sections or a new scope: the panes whose text the search hears of, the
  /// panes that hand it their find commands, and a search text to take anew.
  private func panesDidChange() {
    var panes: [PaneView] = []
    for section in sectionsInScope where !panes.contains(where: { $0 === section.pane }) {
      panes.append(section.pane)
    }
    self.panes = panes
    var allPanes: [PaneView] = []
    for section in sections where !allPanes.contains(where: { $0 === section.pane }) {
      allPanes.append(section.pane)
    }
    let center = NotificationCenter.default
    for pane in observedPanes where !allPanes.contains(where: { $0 === pane }) {
      center.removeObserver(
        self, name: NSTextStorage.willProcessEditingNotification, object: pane.textView.textStorage)
      if pane.textView.search === self {
        pane.textView.search = nil
      }
    }
    for pane in allPanes where !observedPanes.contains(where: { $0 === pane }) {
      center.addObserver(
        self, selector: #selector(textWillProcessEditing(_:)),
        name: NSTextStorage.willProcessEditingNotification, object: pane.textView.textStorage)
      pane.textView.search = self
    }
    observedPanes = allPanes
    textWillChange()
  }

  @objc private func textWillProcessEditing(_ notification: Notification) {
    guard let textStorage = notification.object as? NSTextStorage,
      textStorage.editedMask.contains(.editedCharacters)
    else { return }
    textWillChange()
  }

  /// Tells the finder that the text it searches is about to change, and has the search text
  /// taken anew when it is next asked for.
  private func textWillChange() {
    finder.noteClientStringWillChange()
    isTextStale = true
    // The ranges of the matches refer to the text as it was.
    matchesAreCurrent = false
    showMatches(.none)
  }

  /// Marks the matches that the finder has found so far in their panes and tells the delegate.
  ///
  /// The finder hands over its matches bit by bit, each time all of them so far, which may be
  /// hundreds of thousands. Where each lies in its pane is worked out away from the main actor,
  /// one handover at a time: the matches under way show first, then all that the finder found
  /// meanwhile. The finder's array makes an object for each match as it is read, on the main
  /// actor; it is read in parts, and the main actor is let go between them.
  ///
  /// The finder drops its matches once the focus leaves the search field, as after Find Next or
  /// on the way to the field for replacing; they hold all the same until the text or the panes
  /// change, and stay while the bar is open.
  private func matchesDidChange() {
    guard findBar.isFindBarVisible else { return showMatches(.none) }
    guard matchesInPreparation == nil else {
      hasMatchesWaiting = true
      return
    }
    let values = finder.incrementalMatchRanges
    // Matches of a text that has changed since, which the finder found before it heard of the
    // change, have no place in the text as it is now.
    guard !values.isEmpty || findBar.holdsSearchFocus, !isTextStale else { return }
    let text = searchText()
    let grids = panes.map(\.textView.grid)
    matchesInPreparation = Task {
      let ranges = await Self.ranges(of: values as NSArray)
      // Cancelled once the text or the panes changed.
      guard !Task.isCancelled else { return }
      let found = await FoundMatches.placing(ranges, in: text, grids: grids)
      // Cancelled once the text or the panes changed.
      guard !Task.isCancelled else { return }
      matchesInPreparation = nil
      let isWaiting = hasMatchesWaiting
      hasMatchesWaiting = false
      hasFoundMatches = !found.places.isEmpty
      matchesAreCurrent = true
      showMatches(found)
      if isWaiting {
        matchesDidChange()
      }
    }
  }

  /// How many matches of the finder are read at a stretch on the main actor, about 20 ms.
  static let matchesReadAtOnce = 200_000

  /// The ranges of `values`, the matches of the finder, read on the main actor in parts of
  /// ``matchesReadAtOnce``, letting it go between them; as far as read once the task is
  /// cancelled.
  ///
  /// The array holds the finder's matches as they were when it handed them over; it does not
  /// change as the finder goes on.
  private static func ranges(of values: NSArray) async -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    ranges.reserveCapacity(values.count)
    var start = 0
    while start < values.count, !Task.isCancelled {
      if start > 0 {
        await Task.yield()
      }
      let part = NSRange(location: start, length: min(matchesReadAtOnce, values.count - start))
      // Enumerating a part of the array fetches its values many at a time.
      for case let value as NSValue in values.subarray(with: part) as NSArray {
        if let range = Range(value.rangeValue) {
          ranges.append(range)
        }
      }
      start = NSMaxRange(part)
    }
    return ranges
  }

  private func showMatches(_ found: FoundMatches) {
    if found.places.isEmpty {
      matchesInPreparation?.cancel()
      matchesInPreparation = nil
      hasMatchesWaiting = false
    }
    let shown = found.rangesByPane.indices.filter { !found.rangesByPane[$0].isEmpty }.map {
      panes[$0]
    }
    for pane in panesWithMatches where !shown.contains(where: { $0 === pane }) {
      pane.textView.searchMatches = []
    }
    for (index, ranges) in found.rangesByPane.enumerated() where !ranges.isEmpty {
      panes[index].textView.searchMatches = ranges
    }
    panesWithMatches = shown
    guard !(found.places.isEmpty && self.found.places.isEmpty) else { return }
    self.found = found
    listedMatches = nil
    delegate?.paneSearchDidChangeMatches(self)
  }
}
