import AppKit
import MergeModel
import PaneKit

extension SessionCommand {
  /// What must hold for a command to have an effect, which the window checks to validate it.
  enum Requirement {
    /// A jump needs a block to land on.
    case jumpTarget(BlockNavigation.Jump)

    /// Going to the other end of a move needs a current block that is an end of one.
    case moveEnd

    /// Moving the focus needs another pane in view.
    case anotherPane

    /// Another file of the window lies in the direction, after or before the one shown.
    case anotherFile(forward: Bool)

    /// Showing identical files needs a window that compares two folders.
    case comparedFolders

    /// Filtering the files needs a list of them.
    case fileList

    /// A command of the search needs the search to be able to carry out its action, such as a
    /// text to search for.
    case search(NSTextFinder.Action)

    /// Replacing all matches needs the find bar to show its field for replacing, which limits
    /// the search to the result, and a match that the search found there; the find bar itself
    /// offers only Replace.
    case replacing

    /// Choosing a comparison mode needs no comparison under way.
    case noComparisonUnderWay

    /// Using ignore rules needs a comparison of two files, not a merge, a rule in Settings that
    /// is switched on and can take effect, and no comparison under way.
    case ignoreRules

    /// Hiding or showing the base needs a base and the panes above the result in view.
    case basePane

    /// Coupling the panes while they scroll needs the panes side by side in view, not the single
    /// column.
    case panesSideBySide

    /// Showing a single column needs a comparison of two files.
    case singleColumn

    /// Showing all lines needs a collapsed run.
    case collapsedRows

    /// Showing the places of ignored changes needs a place where a line differs in a way the
    /// comparison ignores; a line that differs only in its line ending has none.
    case ignoredChanges

    /// Collapsing needs a run of unchanged lines without work that is expanded.
    case collapsibleRows

    /// Zooming in needs a larger size left.
    case largerFontSize

    /// Zooming out needs a smaller size left.
    case smallerFontSize

    /// Actual Size needs another size than the standard one.
    case otherFontSize

    /// Opening the file needs one on disk.
    case fileOnDisk

    /// Copying a block needs a current block with text.
    case blockText

    /// A patch needs a comparison, not a merge, with a file whose bytes differ and whose lines
    /// it can show, or a window of several files with one that changed.
    case patch

    /// Maximizing the result needs a result.
    case resultPane

    /// Swapping the sides needs a comparison of two files.
    case swappableSides

    /// Skipping the remaining files needs a run of `git difftool` with files left after this
    /// one, as far as Git tells.
    case remainingFiles

    /// Choosing sources needs a current block in a merge, in which the roles take part and that
    /// does not have their texts already.
    case choice([Role])

    /// Switching a toggle needs a current block in a merge, in which the role takes part, and a
    /// toggle that may switch.
    case toggle(Role)

    /// Resolving by hand needs a current block in a merge whose result is in view.
    case currentResultBlock

    /// Resetting the current block needs one that differs from how it was loaded.
    case resettableBlock

    /// Reopening the conflicts needs a conflict that differs from how it was loaded.
    case resettableConflicts

    /// Resetting every block needs one that differs from how it was loaded.
    case resettableBlocks

    /// Resolving the open conflicts needs one.
    case openConflicts

    /// Saving as needs the result of a merge whose files the window shows.
    case result

    /// Saving needs the result of a merge whose files the window shows, or a file of a
    /// comparison with copied changes that are not saved.
    case changes

    /// Leaving a merge unresolved needs someone who waits for it.
    case waitingCaller

    /// Choosing other files needs a session that the user put together, not one that Git
    /// started, whose files the window shows.
    case ownFiles

    /// Copying needs a comparison in which the side `direction` points to may be written and
    /// the text of the other side shows, no comparison under way, and a changed block: the
    /// current one, or for `allChanges` any.
    case copy(PaneSeam.CopyDirection, allChanges: Bool)

    /// The command always has an effect.
    case nothing
  }

  /// What the command needs to have an effect.
  var requirement: Requirement {
    switch self {
    case .nextConflict: .jumpTarget(.nextOpenConflict)
    case .previousConflict: .jumpTarget(.previousOpenConflict)
    case .nextChange: .jumpTarget(.nextChange)
    case .previousChange: .jumpTarget(.previousChange)
    case .firstChange: .jumpTarget(.firstChange)
    case .lastChange: .jumpTarget(.lastChange)
    case .nextFile: .anotherFile(forward: true)
    case .previousFile: .anotherFile(forward: false)
    case .nextPane, .previousPane: .anotherPane
    case .toggleIdenticalFiles: .comparedFolders
    case .filterFiles: .fileList
    case .findAndReplace: .resultPane
    case .replaceAll: .replacing
    case .findNext: .search(.nextMatch)
    case .findPrevious: .search(.previousMatch)
    case .useSelectionForFind: .search(.setSearchString)
    case .compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges, .ignoreAllWhitespace:
      .noComparisonUnderWay
    case .toggleIgnoreRules: .ignoreRules
    case .toggleBase: .basePane
    case .toggleScrollSynchronization: .panesSideBySide
    case .showSingleColumn: .singleColumn
    case .showAllLines: .collapsedRows
    case .collapseUnchangedLines: .collapsibleRows
    case .zoomIn: .largerFontSize
    case .zoomOut: .smallerFontSize
    case .actualSize: .otherFontSize
    case .openInEditor: .fileOnDisk
    case .copyBlock: .blockText
    case .copyPatch, .exportPatch: .patch
    case .toggleResultMaximized: .resultPane
    case .swapSides: .swappableSides
    case .goToOtherEndOfMove: .moveEnd
    case .skipRemainingFiles: .remainingFiles
    case .save, .saveAndClose: .changes
    case .saveAs: .result
    case .leaveUnresolved: .waitingCaller
    case .changeFiles: .ownFiles
    case .toggleIgnoredChanges: .ignoredChanges
    case .showAlignedLines, .showConnectedSides, .toggleSyntaxHighlighting, .toggleInvisibles,
      .toggleLineWrapping, .toggleFooter, .goToLine, .find:
      .nothing
    case .useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone: .choice(chosenRoles ?? [])
    case .toggleSourceA: .toggle(.a)
    case .toggleSourceBase: .toggle(.base)
    case .toggleSourceB: .toggle(.b)
    case .resolveManually: .currentResultBlock
    case .resetChange: .resettableBlock
    case .reopenAllConflicts: .resettableConflicts
    case .resetAllDecisions: .resettableBlocks
    case .resolveAllWithA, .resolveAllWithB: .openConflicts
    case .copyToRight, .copyToLeft, .copyAllChangesToRight, .copyAllChangesToLeft:
      copy.map { .copy($0.direction, allChanges: $0.allChanges) } ?? .nothing
    }
  }
}
