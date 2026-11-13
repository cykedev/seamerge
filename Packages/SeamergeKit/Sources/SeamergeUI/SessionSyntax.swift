import Foundation
import MergeModel
import SyntaxKit

/// The tokens of the files of a window, lexed by the syntax of their language: each input once,
/// in the background, so that the window shows its lines before they have colors.
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

  /// Colors the files of a window as `language`, or not at all.
  init(language: LanguageDescription?) {
    self.language = language
  }

  isolated deinit {
    for source in sources.values {
      source.lexing?.cancel()
    }
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
    for role in session.roles {
      let text = session.file(for: role)?.text ?? ""
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

  /// The tokens of `text` in `language`, lexed away from the main actor.
  @concurrent
  nonisolated static func lex(_ text: String, as language: LanguageDescription) async -> LexedText {
    LexedText(
      language: language, lines: text.split(separator: "\n", omittingEmptySubsequences: false))
  }

  /// The language of the files of `session`, recognized by the name of the result or, for a
  /// comparison, of the newer file, and failing that by the first line of that file.
  static func language(of session: Session, resultURL: URL?) -> LanguageDescription {
    let file = session.file(for: .b) ?? session.file(for: .a)
    let name = resultURL?.lastPathComponent ?? file?.url?.lastPathComponent ?? file?.label ?? ""
    let firstLine = file?.text.map { String($0.prefix { !$0.isNewline }) } ?? ""
    return LanguageDescription(fileName: name, firstLine: firstLine)
  }

}
