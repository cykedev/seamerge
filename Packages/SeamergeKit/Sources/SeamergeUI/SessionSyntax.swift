import Foundation
import MergeModel
import PaneKit
import SyntaxKit
import TextBasics

/// The tokens of the files of a window, lexed by the syntax of their language: each input once,
/// in the background, so that the window shows its lines before they have colors, and the result
/// as it changes, from the changed lines on only as far as the change reaches.
///
/// The window gives each pane the tokens of its file once they are known; the presentation learns
/// of them through ``onLexed``.
@MainActor
final class SessionSyntax {
  /// The language the code is colored as, or `nil` while it is not colored.
  ///
  /// A new language lexes every file anew; until then, the files have no tokens.
  var language: LanguageDescription? {
    didSet {
      guard language != oldValue else { return }
      for source in sources.values {
        source.lexing?.cancel()
      }
      sources.removeAll()
      resultLexing?.cancel()
      resultLexing = nil
      resultTextToLex = nil
      resultTokens = nil
      onLexed()
    }
  }

  /// Called once tokens of some file are known, or when the known ones are gone.
  var onLexed: () -> Void = {}

  /// The tokens of each input, with the text they were lexed from, as far as they are known.
  private var sources: [Role: Source] = [:]

  private struct Source {
    /// The text of the file that was lexed.
    let text: String

    /// The tokens, or while the text is still being lexed those of the text before, if any.
    var tokens: SyntaxTokens?

    /// The lexing under way, or `nil` once it is over.
    var lexing: Task<Void, Never>?
  }

  /// The tokens of the rows of the result, or `nil` while none are known; while the result is
  /// being lexed anew, those of its text before.
  private(set) var resultTokens: SyntaxTokens?

  /// The lexing of the whole result under way, or `nil` if there is none.
  private var resultLexing: Task<Void, Never>?

  /// The text of the result that changed while it was being lexed, to lex once that is over.
  private var resultTextToLex: String?

  /// Colors the files of a window as `language`, or not at all.
  init(language: LanguageDescription?) {
    self.language = language
  }

  isolated deinit {
    for source in sources.values {
      source.lexing?.cancel()
    }
    resultLexing?.cancel()
  }

  /// The tokens of the input of `role`, or `nil` while none are known.
  func tokens(of role: Role) -> SyntaxTokens? {
    sources[role]?.tokens
  }

  /// Lexes the inputs of `session` whose text the tokens do not stem from yet, in the
  /// background; the tokens of inputs whose text stayed the same stay, and those of the others
  /// until their new ones are known.
  func lexInputs(of session: Session) {
    guard let language else { return }
    for (role, file) in session.inputs {
      let text = file.text ?? ""
      if let source = sources[role], source.text == text { continue }
      sources[role]?.lexing?.cancel()
      sources[role] = Source(
        text: text, tokens: sources[role]?.tokens,
        lexing: Task { [weak self] in
          let lexed = await Self.lex(text, as: language)
          guard !Task.isCancelled, let self, self.sources[role]?.text == text else { return }
          self.sources[role]?.tokens = SyntaxTokens(lexed)
          self.sources[role]?.lexing = nil
          self.onLexed()
        })
    }
  }

  /// Lexes the whole result, whose pane shows `rows`, in the background; until then, the tokens
  /// it had stay, so that its colors do not flicker.
  ///
  /// While a lexing of the result is under way, it lexes the latest text once it is over, so
  /// that a burst of changes costs one more lexing rather than one each.
  func lexResult(_ rows: ResultPaneContent.Rows) {
    resultTextToLex = rows.text
    if resultLexing == nil {
      lexLatestResult()
    }
  }

  /// Lexes the text of the result last asked for, unless there is none.
  private func lexLatestResult() {
    guard let language, let text = resultTextToLex else { return }
    resultTextToLex = nil
    resultLexing = Task { [weak self] in
      let lexed = await Self.lex(text, as: language)
      guard !Task.isCancelled, let self else { return }
      self.resultLexing = nil
      guard self.resultTextToLex == nil else {
        self.lexLatestResult()
        return
      }
      self.resultTokens = SyntaxTokens(lexed)
      self.onLexed()
    }
  }

  /// Lexes again the rows of the result that `edits` rewrote, which changed the rows of its
  /// pane from `old` to `new`, and the rows after them as far as the change reaches.
  ///
  /// The edits follow each other, each in the text the ones before it left, in the offsets of
  /// the pane's text. Typing usually costs one row.
  ///
  /// - Returns: The rows of `new` whose tokens changed, or `nil` if the tokens are lexed anew in
  ///   the background, as while they are not known yet or if the edits do not lead from `old`
  ///   to `new`.
  func resultDidChange(
    by edits: [PaneEdit], from old: ResultPaneContent.Rows, to new: ResultPaneContent.Rows
  ) -> Range<Int>? {
    guard language != nil else { return nil }
    guard let tokens = resultTokens, resultLexing == nil,
      let change = Self.rowChange(of: edits, from: old.starts), change.starts == new.starts
    else {
      lexResult(new)
      return nil
    }
    let text = new.text.utf16
    return tokens.lexed.replaceLines(in: change.oldRows, withLineCount: change.newRowCount) {
      row in
      let start = text.index(text.startIndex, offsetBy: new.starts[row])
      let end = text.index(text.startIndex, offsetBy: new.starts[row + 1] - 1)
      return Substring(text[start..<end])
    }
  }

  /// The rows that `edits` rewrote as one stretch, in the rows before the edits, the number of
  /// rows that took their place, and where the rows start after the edits, given where they
  /// start before; `nil` if an edit lies beyond the text.
  ///
  /// The stretch reaches from the first row an edit touched to the last, so that edits apart
  /// from each other, as of a command, take the rows between them along.
  static func rowChange(
    of edits: [PaneEdit], from starts: LineStarts
  ) -> (oldRows: Range<Int>, newRowCount: Int, starts: LineStarts)? {
    var starts = starts
    var stretch: (start: Int, oldEnd: Int, newEnd: Int)?
    for edit in edits {
      guard edit.range.upperBound < starts[starts.lineCount] else { return nil }
      let first = starts.line(containing: edit.range.lowerBound)
      let end = starts.line(containing: edit.range.upperBound) + 1
      let breaks = edit.text.utf16.enumerated().filter { $0.element == Self.lineFeed }
      let delta = edit.text.utf16.count - edit.range.count
      starts.replaceLines(
        first..<end, withLinesStartingAt: breaks.map { edit.range.lowerBound + $0.offset + 1 },
        movingLaterLinesBy: delta)
      let newEnd = first + breaks.count + 1
      guard let previous = stretch else {
        stretch = (first, end, newEnd)
        continue
      }
      // Both stretches together, in the rows before this edit, then after it.
      let union = max(previous.newEnd, end)
      stretch = (
        min(previous.start, first), previous.oldEnd + union - previous.newEnd,
        union + newEnd - end
      )
    }
    guard let stretch else { return nil }
    return (stretch.start..<stretch.oldEnd, stretch.newEnd - stretch.start, starts)
  }

  private static let lineFeed = UInt16(UInt8(ascii: "\n"))

  /// The tokens of `text` in `language`, lexed away from the main actor.
  @concurrent
  nonisolated static func lex(_ text: String, as language: LanguageDescription) async -> LexedText {
    LexedText(
      language: language, lines: text.split(separator: "\n", omittingEmptySubsequences: false))
  }

  /// The language of the files of `session`, recognized by the name of the result or, for a
  /// comparison, of the newer file, and failing that by the first line of that file.
  static func language(of session: Session, resultURL: URL?) -> LanguageDescription {
    let file = session.inputs.b
    // A file of a single line of megabytes would take long to read to its end.
    let firstLine =
      file.text.map { String($0.prefix(firstLineLength).prefix { !$0.isNewline }) } ?? ""
    return LanguageDescription(
      fileName: path(of: session, resultURL: resultURL), firstLine: firstLine)
  }

  /// How much of the first line of a file names its language: a `#!` line names its
  /// interpreter within its first few hundred characters.
  private static let firstLineLength = 1024

  /// The path of the file that names the language of `session`: the result, or for a comparison
  /// the newer file; its label if it has no path.
  static func path(of session: Session, resultURL: URL?) -> String {
    let file = session.inputs.b
    return resultURL?.path ?? file.url?.path ?? file.label
  }
}
