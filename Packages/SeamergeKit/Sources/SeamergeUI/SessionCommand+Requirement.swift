extension SessionCommand {
  /// What must hold for a command to have an effect, which the window checks to validate it.
  enum Requirement {
    /// A jump needs a block to land on.
    case jumpTarget(BlockNavigation.Jump)

    /// Moving the focus needs another pane in view.
    case anotherPane

    /// Choosing a comparison mode needs no comparison under way.
    case noComparisonUnderWay

    /// Copying a block needs a current block with text.
    case blockText
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
    case .copyBlock: .blockText
    }
  }
}
