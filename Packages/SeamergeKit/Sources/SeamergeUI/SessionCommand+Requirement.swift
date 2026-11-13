import MergeModel

extension SessionCommand {
  /// What must hold for a command to have an effect, which the window checks to validate it.
  enum Requirement {
    /// A jump needs a block to land on.
    case jumpTarget(BlockNavigation.Jump)

    /// Moving the focus needs another pane in view.
    case anotherPane

    /// Choosing a comparison mode needs no comparison under way.
    case noComparisonUnderWay

    /// Hiding or showing the base needs a base and the panes above the result in view.
    case basePane

    /// Showing all lines needs a collapsed run.
    case collapsedRows

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

    /// Resolving the open conflicts needs one.
    case openConflicts

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
    case .nextPane, .previousPane: .anotherPane
    case .compareExactly, .ignoreLineEndings, .ignoreWhitespaceChanges, .ignoreAllWhitespace:
      .noComparisonUnderWay
    case .toggleBase: .basePane
    case .showAllLines: .collapsedRows
    case .collapseUnchangedLines: .collapsibleRows
    case .zoomIn: .largerFontSize
    case .zoomOut: .smallerFontSize
    case .actualSize: .otherFontSize
    case .openInEditor: .fileOnDisk
    case .copyBlock: .blockText
    case .toggleResultMaximized: .resultPane
    case .swapSides: .swappableSides
    case .skipRemainingFiles: .remainingFiles
    case .toggleScrollSynchronization, .toggleInvisibles, .goToLine: .nothing
    case .useA, .useBase, .useB, .useAThenB, .useBThenA, .useNone: .choice(chosenRoles ?? [])
    case .toggleSourceA: .toggle(.a)
    case .toggleSourceBase: .toggle(.base)
    case .toggleSourceB: .toggle(.b)
    case .resolveManually: .currentResultBlock
    case .resolveAllWithA, .resolveAllWithB: .openConflicts
    }
  }
}
