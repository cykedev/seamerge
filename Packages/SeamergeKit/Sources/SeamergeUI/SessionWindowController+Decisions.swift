import AppKit
import MergeModel
import PaneKit

/// The decisions of a merge: choosing sources for the current block, switching its toggles,
/// resolving it by hand, and resolving every open conflict at once.
extension SessionWindowController {
  /// Takes only A's text for the current block.
  @objc func useA(_ sender: Any?) {
    choose(.useA)
  }

  /// Takes only the base's text for the current block.
  @objc func useBase(_ sender: Any?) {
    choose(.useBase)
  }

  /// Takes only B's text for the current block.
  @objc func useB(_ sender: Any?) {
    choose(.useB)
  }

  /// Takes A's text, then B's, for the current block.
  @objc func useAThenB(_ sender: Any?) {
    choose(.useAThenB)
  }

  /// Takes B's text, then A's, for the current block.
  @objc func useBThenA(_ sender: Any?) {
    choose(.useBThenA)
  }

  /// Takes nothing for the current block.
  @objc func useNone(_ sender: Any?) {
    choose(.useNone)
  }

  /// Switches A on or off for the current block.
  @objc func toggleSourceA(_ sender: Any?) {
    toggle(.toggleSourceA)
  }

  /// Switches the base on or off for the current block.
  @objc func toggleSourceBase(_ sender: Any?) {
    toggle(.toggleSourceBase)
  }

  /// Switches B on or off for the current block.
  @objc func toggleSourceB(_ sender: Any?) {
    toggle(.toggleSourceB)
  }

  /// Turns the current block into text to edit by hand: the preview of an open conflict becomes
  /// text, an empty block gets an empty line; then the insertion point goes to its start, in text
  /// mode.
  @objc func resolveManually(_ sender: Any?) {
    guard canPerform(.resolveManually), let block = currentResultBlock,
      let result = presentation.result, let resultPane = layout.resultPane, let window
    else { return }
    let resolution = result.document.planResolvingByHand(block)
    resultUndo.carryOut(resolution.plan, named: SessionCommand.resolveManually.undoName ?? "")
    if let current = presentation.currentBlock {
      announceState(ofBlock: current)
    }
    window.makeFirstResponder(resultPane.documentView)
    guard let resolved = presentation.result else { return }
    let caret = resolved.resultText.paneOffset(ofFileOffset: resolution.cursorPosition)
    resultPane.documentView.setSelectedRange(NSRange(location: caret, length: 0))
    resultPane.documentView.scrollRangeToVisible(resultPane.documentView.selectedRange())
  }

  /// Resolves every open conflict with A's text.
  @objc func resolveAllWithA(_ sender: Any?) {
    resolveOpenConflicts(with: .a, command: .resolveAllWithA)
  }

  /// Resolves every open conflict with B's text.
  @objc func resolveAllWithB(_ sender: Any?) {
    resolveOpenConflicts(with: .b, command: .resolveAllWithB)
  }

  /// The block that block commands act on: the current block of a merge.
  var currentResultBlock: Block? {
    guard presentation.result != nil, let current = presentation.currentBlock else { return nil }
    return presentation.changes.blocks[current]
  }

  /// The plan that takes the texts of `roles` for the current block, or `nil` if there is no
  /// current block of a merge or one of the roles takes no part in it.
  func decisionPlan(choosing roles: [Role]) -> EditPlan? {
    guard let block = currentResultBlock, let document = presentation.result?.document,
      roles.allSatisfy({ takesPart($0, in: block, of: document) })
    else { return nil }
    return document.planChoosing(roles, in: block)
  }

  /// The plan that switches the toggle of `role` for the current block, or `nil` if there is no
  /// current block of a merge or the role takes no part in it.
  func decisionPlan(toggling role: Role) -> EditPlan? {
    guard let block = currentResultBlock, let document = presentation.result?.document,
      takesPart(role, in: block, of: document)
    else { return nil }
    return document.planToggling(role, in: block)
  }

  /// Whether the toggle of `role` is on for the current block: its text is taken there, and the
  /// block is no open conflict.
  func isSourceOn(_ role: Role) -> Bool {
    guard let block = currentResultBlock, let document = presentation.result?.document else {
      return false
    }
    let segment = document.segment(for: block)
    guard segment.state != .open, takesPart(role, in: block, of: document) else { return false }
    let toggle = document.toggles(in: block).first { $0.roles.contains(role) }
    return toggle.map { Set(segment.sources).isSuperset(of: $0.roles) } ?? false
  }

  /// The commands that choose sources for the current block and differ in what they give it,
  /// in the order of ``SessionCommand/choices``.
  ///
  /// Commands can give the same sources, as when A and B share a toggle or one side removed the
  /// lines; of those, only the simplest is listed.
  var distinctChoices: [SessionCommand] {
    guard let block = currentResultBlock, let document = presentation.result?.document else {
      return []
    }
    var givenSources: [[Role]] = []
    var distinct: Set<SessionCommand> = []
    for command in SessionCommand.choicesBySimplicity {
      guard let roles = command.chosenRoles,
        roles.allSatisfy({ takesPart($0, in: block, of: document) })
      else { continue }
      let sources = document.sourcesChoosing(roles, in: block)
      guard !givenSources.contains(sources) else { continue }
      givenSources.append(sources)
      distinct.insert(command)
    }
    return SessionCommand.choices.filter(distinct.contains)
  }

  /// The command among ``distinctChoices`` whose outcome the current block holds, if any: none
  /// for an open conflict and none once the block was edited by hand.
  var currentChoice: SessionCommand? {
    distinctChoices.first { decisionPlan(choosing: $0.chosenRoles ?? [])?.isEmpty == true }
  }

  /// Whether `role` takes part in `block`, which it does unless it is the base of a merge
  /// without one.
  private func takesPart(_ role: Role, in block: Block, of document: ResultDocument) -> Bool {
    document.toggles(in: block).contains { $0.roles.contains(role) }
  }

  /// Carries out `command`, which chooses the sources of the current block, and goes on to the
  /// next open conflict if the block was an open conflict before and the settings say so.
  ///
  /// From any other block, above all one edited by hand, the selection stays, so that the user
  /// sees what the command did.
  private func choose(_ command: SessionCommand) {
    guard canPerform(command), let block = presentation.currentBlock,
      let plan = decisionPlan(choosing: command.chosenRoles ?? [])
    else { return }
    let wasOpen = presentation.navigation.isOpenConflict[block]
    resultUndo.carryOut(plan, named: command.undoName ?? command.title)
    announceState(ofBlock: block)
    if wasOpen, settings.goesToNextConflict,
      let next = presentation.navigation.target(of: .nextOpenConflict)
    {
      presentation.jump(to: next)
    }
  }

  /// Carries out `command`, which switches a toggle of the current block; the selection stays,
  /// so that further toggles add to the block in the order they are switched on.
  private func toggle(_ command: SessionCommand) {
    guard canPerform(command), let role = command.toggledRole,
      let block = presentation.currentBlock,
      let plan = decisionPlan(toggling: role)
    else { return }
    resultUndo.carryOut(plan, named: command.undoName ?? command.title)
    announceState(ofBlock: block)
  }

  /// Resolves every open conflict with the text of `role`, as `command` does.
  private func resolveOpenConflicts(with role: Role, command: SessionCommand) {
    guard canPerform(command), let document = presentation.result?.document else { return }
    resultUndo.carryOut(
      document.planResolvingOpenConflicts(with: [role]), named: command.undoName ?? command.title)
    presentation.announceOutcome(command.undoName ?? command.title)
  }

  /// Tells VoiceOver how changed block `block` stands after a command, with the open
  /// conflicts that are left.
  func announceState(ofBlock block: Int) {
    guard let state = presentation.decisionColumn?.decisions[block]?.state.spokenName else {
      return
    }
    presentation.announceOutcome(state)
  }
}
