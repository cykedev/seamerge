import Foundation
import MergeModel
import PaneKit
import os

/// Editing the result: typing goes through the plans of the result document, and commands carry
/// out plans in the result pane, so that the text of the pane and the segments of the document
/// never part.
extension SessionPresentation {
  /// Carries out `plan`, a plan of the result document for a command, in the result pane and the
  /// document, shows the outcome, and returns the step that takes it back; `nil` for a
  /// comparison, which has no result to carry it out in.
  ///
  /// - Precondition: `plan` was made for the result as it is.
  func carryOut(_ plan: EditPlan) -> UndoStep? {
    guard let result, let resultPane = layout.resultPane else { return nil }
    pendingTyping = nil
    var text = result.resultText
    var edits: [PaneEdit] = []
    var replacedTexts: [String] = []
    for replacement in plan.replacements {
      let (edit, replacedText) = text.carryOut(replacement)
      edits.append(edit)
      replacedTexts.append(replacedText)
    }
    var document = result.document
    let step = document.apply(plan, replacedTexts: replacedTexts)
    isCarryingOut = true
    resultPane.carryOut(edits)
    isCarryingOut = false
    show(ResultState(document: document, resultText: text), in: resultPane, after: edits)
    return step
  }

  /// Tells VoiceOver `outcome`, what a command or undo did, with the open conflicts that are
  /// left, in the words of the toolbar.
  func announceOutcome(_ outcome: String) {
    guard let document = result?.document else { return }
    let count = SessionToolbar.countText(
      openConflictCount: document.openConflictCount,
      hasConflicts: changes.blocks.contains { $0.kind == .conflict })
    announce(
      String(
        localized: "\(outcome). \(count)", bundle: .module,
        comment: "VoiceOver after a decision, such as Chosen: B. 2 Conflicts Left."))
  }
}

extension SessionPresentation: PaneEditingDelegate {
  /// The edits that carry out an edit of the user in the result, as the document attributes it
  /// to the segments: the edit itself, or edits around the previews in its range; none if it
  /// would only change previews.
  ///
  /// Line breaks of the edit's text become line feeds, as the pane shows every line break.
  func pane(_ pane: PaneView, editsFor edit: PaneEdit) -> [PaneEdit] {
    pendingTyping = nil
    guard pane === layout.resultPane, let result else { return [] }
    let typed = PaneEdit(range: edit.range, text: ResultText.visibleForm(of: edit.text))
    let plan = result.document.plan(for: result.resultText.replacement(for: typed))
    guard !plan.isEmpty else { return [] }
    var text = result.resultText
    let edits = plan.replacements.map { text.carryOut($0).edit }
    pendingTyping = (plan, edits)
    return edits
  }

  /// Takes over the edits that the pane carried out for the user into the document and shows
  /// the outcome; the delegate learns of the step that takes them back.
  func pane(_ pane: PaneView, didCarryOut edits: [PaneEdit], replacing replacedTexts: [String]) {
    guard let result else { return }
    guard let pending = pendingTyping, pending.edits == edits else {
      // Only edits that the document planned should reach here.
      pendingTyping = nil
      Self.logger.error("The result pane carried out edits that were not planned")
      show(edits.reduce(result) { Self.attributing($1, to: $0) }, in: pane, anew: true)
      delegate?.presentationDidTakeOverUnannouncedChange(self)
      return
    }
    pendingTyping = nil
    var text = result.resultText
    let replaced = pending.plan.replacements.map { text.carryOut($0).replacedText }
    var document = result.document
    let step = document.apply(pending.plan, replacedTexts: replaced)
    show(ResultState(document: document, resultText: text), in: pane, after: edits)
    if let first = edits.first, let last = edits.last {
      delegate?.presentation(
        self, didType: step, at: first.range,
        caret: last.range.lowerBound + last.text.utf16.count)
    }
    // The selection moved while the edit was under way, which followed nothing.
    followInsertionPoint()
  }

  /// Takes over a change of the result pane that nobody announced, as typing would be
  /// attributed, and shows the result anew once the change is over; the undo history ends here,
  /// since the steps before it no longer fit the text.
  ///
  /// The document follows each such change at once, so that a second one before the result is
  /// shown again is attributed to the text the first one left.
  func pane(_ pane: PaneView, didChangeTextWithoutAnnouncing edit: PaneEdit) {
    pendingTyping = nil
    guard let result else { return }
    Self.logger.error(
      "The result changed without an announcement at \(edit.range, privacy: .public)")
    takeOverUnannounced(Self.attributing(edit, to: result), in: pane)
  }

  /// `result` after `edit` of the pane's text, attributed to the segments as typing is.
  private static func attributing(_ edit: PaneEdit, to result: ResultState) -> ResultState {
    let typed = PaneEdit(range: edit.range, text: ResultText.visibleForm(of: edit.text))
    var text = result.resultText
    let plan = result.document.plan(for: text.replacement(for: typed))
    let replaced = plan.replacements.map { text.carryOut($0).replacedText }
    var document = result.document
    document.apply(plan, replacedTexts: replaced)
    return ResultState(document: document, resultText: text)
  }
}
