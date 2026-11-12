import Foundation
import GitSupport
import MergeModel

@testable import SeamergeUI

/// Comparisons of small texts for the tests and pictures.
enum SampleDiffs {
  /// Compares `old` with `new`, both named `label`, by default in the mode a window starts in.
  static func diff(
    old: String, new: String, label: String = "Sources/Greeting.swift",
    mode: ComparisonMode = .windowDefault
  ) async throws -> Session {
    try await Session.diff(
      old: SourceFile(bytes: Data(old.utf8), label: label),
      new: SourceFile(bytes: Data(new.utf8), label: label), mode: mode)
  }

  /// A Swift file whose newer version inserts a property, changes a line, and removes a
  /// function: one change of each kind, in that order.
  static func greeting() async throws -> Session {
    try await diff(old: greetingOld, new: greetingNew)
  }

  /// The context of `git difftool` comparing the file of ``greeting()``, the third of twelve
  /// files, before the change on the left and the working copy on the right.
  static let gitContext = SessionContext(
    difftool: DifftoolContext(
      path: "Sources/Greeting.swift", leftRole: .before, rightRole: .workingCopy,
      filePosition: FilePosition(number: 3, count: 12)))

  static let greetingOld = """
    import Foundation

    /// Greets people by name.
    struct Greeter {
      let name: String

      func greeting() -> String {
        "Hello, \\(name)!"
      }

      func introduction() -> String {
        "This is \\(name)."
      }

      func farewell() -> String {
        "Goodbye, \\(name)."
      }
    }

    """

  static let greetingNew = """
    import Foundation

    /// Greets people by name.
    struct Greeter {
      let name: String
      let punctuation: Character = "!"
      var isFormal = false

      func greeting() -> String {
        isFormal ? "Good day, \\(name)\\(punctuation)" : "Hello, \\(name)\\(punctuation)"
      }

      func introduction() -> String {
        "This is \\(name)."
      }
    }

    """

  /// A comparison of `lineCount` lines in which every `spacing`-th line changed, starting at the
  /// third, so that long runs of unchanged lines lie between the changes.
  static func manyChanges(lineCount: Int = 240, spacing: Int = 20) async throws -> Session {
    let old = (1...lineCount).map { "let value\($0) = \($0)" }
    var new = old
    for index in stride(from: 2, to: lineCount, by: spacing) {
      new[index] += " * 2"
    }
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await diff(old: text(old), new: text(new), label: "Sources/Values.swift")
  }

  /// A function, which ``reformattedNew`` formats anew.
  static let reformattedOld = """
    func area(width: Int, height: Int) -> Int {
      return width * height
    }

    """

  /// The function of ``reformattedOld`` with other indentation and spacing, the same code.
  static let reformattedNew = """
    func area(width:Int,height:Int)->Int{
        return width*height
    }

    """
}
