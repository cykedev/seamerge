import AppKit
import PaneKit

/// Decides the edits of a pane the way a test wants and records what the pane reports.
@MainActor
final class EditRecorder: PaneEditingDelegate {
  /// The answer to an edit, the edit itself unless a test says otherwise.
  var answer: (PaneEdit) -> [PaneEdit] = { [$0] }
  private(set) var asked: [PaneEdit] = []
  private(set) var carriedOut: [(edits: [PaneEdit], replacedTexts: [String])] = []
  private(set) var unannounced: [PaneEdit] = []
  /// The text of the pane each time it reported edits as carried out.
  private(set) var textsWhenCarriedOut: [String] = []

  func pane(_ pane: PaneView, editsFor edit: PaneEdit) -> [PaneEdit] {
    asked.append(edit)
    return answer(edit)
  }

  func pane(_ pane: PaneView, didCarryOut edits: [PaneEdit], replacing replacedTexts: [String]) {
    carriedOut.append((edits, replacedTexts))
    textsWhenCarriedOut.append(pane.documentView.string)
  }

  func pane(_ pane: PaneView, didChangeTextWithoutAnnouncing edit: PaneEdit) {
    unannounced.append(edit)
  }

  /// Answers every edit around the given ranges, the way the merge model answers an edit around
  /// the previews of conflicts: the parts of the edited range outside them are replaced from the
  /// last to the first, the first part taking the text.
  func answerAround(_ previews: [Range<Int>]) {
    answer = { edit in
      var parts: [Range<Int>] = []
      var start = edit.range.lowerBound
      for preview in previews where preview.overlaps(edit.range) {
        if start < preview.lowerBound {
          parts.append(start..<preview.lowerBound)
        }
        start = max(start, preview.upperBound)
      }
      if start < edit.range.upperBound || parts.isEmpty {
        parts.append(start..<max(start, edit.range.upperBound))
      }
      return parts.indices.reversed().map { index in
        PaneEdit(range: parts[index], text: index == 0 ? edit.text : "")
      }
    }
  }
}
