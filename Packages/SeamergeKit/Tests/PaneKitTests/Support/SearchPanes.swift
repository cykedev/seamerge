import AppKit
import PaneKit

/// Three panes side by side with one search over them, the find bar below: A with a filler row,
/// the base with a filler row that holds text, and an editable result with previews.
///
/// The sections follow the panes block by block, as a merge reads: the first rows of A, the base
/// and the result, then the rest of each.
@MainActor
final class SearchPanes {
  static let aText = "alpha needle\nneedle\n\nneedle tail"
  static let baseText = "needle\nfiller needle\nneedle"
  static let resultText = "needle\nneedle\npre needle post\nend needle"

  let a = PaneView()
  let base = PaneView()
  let result = PaneView()
  let search = PaneSearch()
  let editor: UndoingEditor
  let observer = SearchObserver()
  let window: KeyWindow

  init() {
    a.content = PaneContent(text: Self.aText, lineNumbers: [0, 1, -1, 2])
    base.content = PaneContent(text: Self.baseText, lineNumbers: [0, -1, 1])
    // The second row is a preview as a whole, the third has one in its middle.
    result.content = PaneContent(
      text: Self.resultText, lineNumbers: [0, 1, 2, 3],
      previews: [PanePreview(range: 7..<14, role: .a), PanePreview(range: 18..<24, role: .b)])
    editor = UndoingEditor()
    result.editingDelegate = editor
    search.sections = [
      PaneSearch.Section(pane: a, rows: 0..<2),
      PaneSearch.Section(pane: base, rows: 0..<2),
      PaneSearch.Section(pane: result, rows: 0..<2),
      PaneSearch.Section(pane: a, rows: 2..<4),
      PaneSearch.Section(pane: base, rows: 2..<3),
      PaneSearch.Section(pane: result, rows: 2..<4),
    ]
    search.delegate = observer
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 400))
    for (index, pane) in [a, base, result].enumerated() {
      pane.frame = CGRect(x: CGFloat(index) * 300, y: 60, width: 300, height: 340)
      container.addSubview(pane)
    }
    search.findBar.frame = CGRect(x: 0, y: 0, width: 900, height: 60)
    container.addSubview(search.findBar)
    window = KeyWindow(
      contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.contentView = container
    container.layoutSubtreeIfNeeded()
    editor.undoManager = result.undoManager
  }

  /// The name of `pane` in expectations.
  func name(of pane: PaneView) -> String {
    pane === a ? "A" : pane === base ? "Base" : pane === result ? "Result" : "?"
  }

  /// The ranges of the search text where `needle` occurs, found part by part the way the finder
  /// reads the text: each part on its own, since each ends with a search boundary.
  func occurrences(of needle: String) -> [NSRange] {
    var found: [NSRange] = []
    var index = 0
    while index < search.stringLength() {
      var part = NSRange()
      var boundary = ObjCBool(false)
      let text =
        search.string(at: index, effectiveRange: &part, endsWithSearchBoundary: &boundary)
        as NSString
      precondition(boundary.boolValue && part.length > 0, "Every part ends with a boundary")
      var start = 0
      while start < text.length {
        let match = text.range(
          of: needle, range: NSRange(location: start, length: text.length - start))
        guard match.location != NSNotFound else { break }
        found.append(NSRange(location: part.location + match.location, length: match.length))
        start = NSMaxRange(match)
      }
      index = NSMaxRange(part)
    }
    return found
  }

  /// The parts of the search text, as the finder reads them.
  func parts() -> [String] {
    var parts: [String] = []
    var index = 0
    while index < search.stringLength() {
      var part = NSRange()
      var boundary = ObjCBool(false)
      parts.append(
        search.string(at: index, effectiveRange: &part, endsWithSearchBoundary: &boundary))
      index = NSMaxRange(part)
    }
    return parts
  }
}

/// Records what a search tells its delegate.
@MainActor
final class SearchObserver: PaneSearchDelegate {
  private(set) var revealed: [PaneSearch.Match] = []

  /// A test waiting for a condition on the matches, with what resumes it.
  private var waiter: (condition: () -> Bool, continuation: CheckedContinuation<Void, Never>)?

  func paneSearch(_ search: PaneSearch, didReveal match: PaneSearch.Match) {
    revealed.append(match)
  }

  func paneSearchDidChangeMatches(_ search: PaneSearch) {
    guard let waiter, waiter.condition() else { return }
    resumeWaiter()
  }

  /// Returns once `condition` holds after a change of the matches, or once the test is
  /// cancelled, as when it runs out of time.
  func waitForMatches(until condition: @escaping () -> Bool) async {
    guard !condition() else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiter = (condition, continuation)
      }
    } onCancel: {
      Task { @MainActor in self.resumeWaiter() }
    }
  }

  private func resumeWaiter() {
    let continuation = waiter?.continuation
    waiter = nil
    continuation?.resume()
  }
}

/// Lets every edit of a pane through and makes each report one group of undo, the way an owner
/// that knows no searches registers its steps.
@MainActor
final class UndoingEditor: PaneEditingDelegate {
  /// The answer to an edit, the edit itself unless a test says otherwise.
  var answer: (PaneEdit) -> [PaneEdit] = { [$0] }
  var undoManager: UndoManager?
  private(set) var asked: [PaneEdit] = []
  private(set) var carriedOut: [[PaneEdit]] = []

  func pane(_ pane: PaneView, editsFor edit: PaneEdit) -> [PaneEdit] {
    asked.append(edit)
    return answer(edit)
  }

  func pane(_ pane: PaneView, didCarryOut edits: [PaneEdit], replacing replacedTexts: [String]) {
    carriedOut.append(edits)
    let inverse = zip(edits, replacedTexts).reversed().map { edit, replaced in
      PaneEdit(
        range: edit.range.lowerBound..<edit.range.lowerBound + edit.text.utf16.count,
        text: replaced)
    }
    guard let undoManager else { return }
    undoManager.beginUndoGrouping()
    undoManager.registerUndo(withTarget: pane) { pane in
      MainActor.assumeIsolated { _ = pane.carryOut(inverse) }
    }
    undoManager.setActionName("Typing")
    undoManager.endUndoGrouping()
  }

  func pane(_ pane: PaneView, didChangeTextWithoutAnnouncing edit: PaneEdit) {}
}
