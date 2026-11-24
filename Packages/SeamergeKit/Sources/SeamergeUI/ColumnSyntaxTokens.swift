import MergeModel
import PaneKit

/// The tokens of the rows of a single column, each the tokens of the line of the file it shows:
/// a row of one side those of its line, a row both sides share those of the second side, whose
/// text it shows.
@MainActor
final class ColumnSyntaxTokens: PaneSyntaxProvider {
  /// The tokens of A, if they are known.
  let a: SyntaxTokens?

  /// The tokens of B, if they are known.
  let b: SyntaxTokens?

  private let column: SingleColumnLayout

  /// Supplies the rows of `column` with the tokens of `a` and `b`.
  init(column: SingleColumnLayout, a: SyntaxTokens?, b: SyntaxTokens?) {
    self.column = column
    self.a = a
    self.b = b
  }

  func tokens(inLine line: Int) -> [PaneToken] {
    guard line >= 0, line < column.rowCount else { return [] }
    let place = column.place(atRow: line)
    let side = place.side ?? PaneContent.otherSide(of: column.firstSide)
    guard let lineOfSide = place.line(in: side) else { return [] }
    return (side == .a ? a : b)?.tokens(inTextLine: lineOfSide) ?? []
  }
}
