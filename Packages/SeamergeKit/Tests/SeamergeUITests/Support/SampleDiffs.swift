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

  /// A comparison of an image that `git difftool` hands over as two temporary copies, which
  /// cannot be compared because the newer one is binary or, with `isBinary` false, cannot be
  /// read.
  static func unavailable(isBinary: Bool) -> UnavailableComparison {
    let folder = URL(filePath: "/private/var/folders/xy/T/", directoryHint: .isDirectory)
    let old = SessionFile(url: folder.appending(path: "Xy12_logo.png"), label: "Assets/logo.png")
    let new = SessionFile(url: folder.appending(path: "Ab34_logo.png"), label: "Assets/logo.png")
    return UnavailableComparison(
      old: old, new: new, reason: isBinary ? .binaryFile(new.url) : .unreadableFile(new.url))
  }

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

  /// A comparison whose changes repeat `repeats` times: a removal of four lines, an insertion
  /// of three and a change of two lines to five, between runs of unchanged lines; with `longLines`
  /// every fourth line is long enough to wrap in a narrow pane.
  static func everyKindOfChange(repeats: Int = 12, longLines: Bool = false) async throws -> Session
  {
    var old: [String] = []
    var new: [String] = []
    func line(_ name: String) -> String {
      let line = "let \(name) = value(\(old.count), \(new.count))"
      guard longLines, (old.count + new.count) % 4 == 0 else { return line }
      return line + String(repeating: " + another term of the sum", count: 6)
    }
    for index in 0..<repeats {
      for number in 0..<6 {
        let same = line("same\(index)_\(number)")
        old.append(same)
        new.append(same)
      }
      let removed = (0..<4).map { line("removed\(index)_\($0)") }
      old += removed
      for number in 0..<5 {
        let same = line("kept\(index)_\(number)")
        old.append(same)
        new.append(same)
      }
      let inserted = (0..<3).map { line("inserted\(index)_\($0)") }
      new += inserted
      for number in 0..<4 {
        let same = line("middle\(index)_\(number)")
        old.append(same)
        new.append(same)
      }
      let before = (0..<2).map { line("before\(index)_\($0)") }
      old += before
      let after = (0..<5).map { line("after\(index)_\($0)") }
      new += after
    }
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await diff(old: text(old), new: text(new), label: "Sources/Kinds.swift")
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
