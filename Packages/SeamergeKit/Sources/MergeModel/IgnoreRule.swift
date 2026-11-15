import Foundation

/// A pattern for text that a comparison of two files does not count, such as a build date.
///
/// The pattern is an ICU regular expression, as `NSRegularExpression` takes it, applied to each
/// line on its own: `^` and `$` stand for the start and the end of the line, and a match never
/// reaches past the line ending. A merge takes no rules.
public struct IgnoreRule: Sendable, Hashable {
  /// Why a rule takes no effect.
  public enum Problem: Sendable, Hashable {
    /// The pattern is not a valid regular expression.
    case invalidPattern

    /// The pattern matches empty text, so it would match every line, such as `.*` or `\s*`.
    case matchesEmptyText

    /// Matching the pattern against a file took longer than ``IgnoreRule/timeLimit``, as a
    /// pattern that backtracks without end does. Only a comparison finds this problem.
    case exceedsTimeLimit
  }

  /// The longest a rule may take to match the lines of one file before it counts as invalid.
  public static let timeLimit: Duration = .seconds(1)

  /// The name shown for the rule, such as “Build date”.
  public var name: String

  /// The regular expression.
  public var pattern: String

  /// Whether comparisons use the rule.
  public var isEnabled: Bool

  /// Creates a rule.
  public init(name: String, pattern: String, isEnabled: Bool = true) {
    self.name = name
    self.pattern = pattern
    self.isEnabled = isEnabled
  }

  /// Why the pattern can take no effect, or `nil` if it can.
  ///
  /// It does not tell whether the pattern exceeds ``timeLimit``, which depends on the text it is
  /// matched against.
  public var problem: Problem? {
    switch validated() {
    case .valid: nil
    case .invalid(let problem): problem
    }
  }

  /// The outcome of compiling and checking a pattern.
  enum Validation {
    /// The pattern compiled and matches no empty text.
    case valid(NSRegularExpression)

    /// The pattern can take no effect.
    case invalid(Problem)
  }

  /// Compiles the pattern and checks that it does not match empty text.
  func validated() -> Validation {
    let expression: NSRegularExpression
    do {
      expression = try NSRegularExpression(pattern: pattern)
    } catch {
      return .invalid(.invalidPattern)
    }
    guard expression.firstMatch(in: "", range: NSRange(location: 0, length: 0)) == nil else {
      return .invalid(.matchesEmptyText)
    }
    return .valid(expression)
  }
}
