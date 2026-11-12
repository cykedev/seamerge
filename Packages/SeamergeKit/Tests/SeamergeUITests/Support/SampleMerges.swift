import Foundation
import MergeModel
import SeamergeUI

/// Merges of small texts for the tests and pictures.
enum SampleMerges {
  /// Merges the given texts, with the label of each file as its name.
  static func merge(
    base: String?, a: String, b: String, options: ComparisonOptions = .init()
  ) async throws -> Session {
    try await Session.merge(
      base: base.map { SourceFile(bytes: Data($0.utf8), label: "base.txt") },
      a: SourceFile(bytes: Data(a.utf8), label: "a.txt"),
      b: SourceFile(bytes: Data(b.utf8), label: "b.txt"), options: options)
  }

  /// The sample merge of P4Merge's documentation, which the window is compared with: a Java
  /// class whose comments A rewrites, whose `main` both sides change differently, and whose
  /// greeting A repeats.
  static func helloWorld() async throws -> Session {
    try await Session.merge(
      base: SourceFile(bytes: Data(helloWorldBase.utf8), label: "HelloWorld0.java"),
      a: SourceFile(bytes: Data(helloWorldA.utf8), label: "HelloWorld1.java"),
      b: SourceFile(bytes: Data(helloWorldB.utf8), label: "HelloWorld2.java"))
  }

  /// The context of the sample merge: the result goes to `HelloWorld.java`.
  static let helloWorldContext = SessionContext(
    resultURL: URL(filePath: "/Users/ada/Documents/color-test/HelloWorld.java"))

  static let helloWorldBase = """
    // This is a multi-line comment
    class HelloWorld0
    {
        // This is a single-line comment
        public static void main(String[] argList)
        {
            System.out.println("Hello World");
        }
    }

    """

  static let helloWorldA = """
    /*
       multi-line comment
    */
    class HelloWorld1
    {
        // single-line comment
        public satic void main(String[] args)
        {
            System.out.println("Hello Java!");
            System.out.println("Hello Java!");
            System.out.println("Hello Java!");
        }
    }

    """

  static let helloWorldB = """
    // This is a multi-line comment
    class HelloWorld0
    {
        // This is a single-line comment
        public static void main(String args[])
        {
            System.out.println("Hello World");
        }
    }

    """

  /// Two changed blocks that touch, each two lines long, in a function of real code.
  enum TouchingBlocks: String, CaseIterable, Sendable {
    /// A changes the first two lines and B the next two: the blocks have different colors on
    /// every pane but the base.
    case differentSides
    /// A changes four lines, and B makes the same change to the last two: a conflict and a
    /// change of both, blue on A and green on B.
    case conflictThenBoth
    /// The same change, merged with the guarded strategy: a change of A and a change of both,
    /// blue on A and yellow on the base.
    case changeThenBoth

    /// The merge of the case.
    func session() async throws -> Session {
      var a = touchingBase
      var b = touchingBase
      let options: ComparisonOptions
      switch self {
      case .differentSides:
        a.replaceSubrange(2..<4, with: touchingA)
        b.replaceSubrange(4..<6, with: touchingB)
        options = ComparisonOptions()
      case .conflictThenBoth, .changeThenBoth:
        a.replaceSubrange(2..<6, with: touchingA + touchingB)
        b.replaceSubrange(4..<6, with: touchingB)
        options = ComparisonOptions(strategy: self == .changeThenBoth ? .guarded : .optimal)
      }
      return try await merge(
        base: lines(touchingBase), a: lines(a), b: lines(b), options: options)
    }

    private func lines(_ lines: [String]) -> String {
      lines.joined(separator: "\n") + "\n"
    }
  }

  private static let touchingBase = [
    "func decode(_ bytes: Data, from encoding: TextEncoding) -> String? {",
    "  switch encoding {",
    "  case .utf8:",
    "    return String(validating: bytes, as: UTF8.self)",
    "  case .utf16LittleEndian:",
    "    return decode(bytes, as: UTF16.self, bigEndian: false)",
    "  case .utf16BigEndian:",
    "    return decode(bytes, as: UTF16.self, bigEndian: true)",
    "  }",
    "}",
  ]

  private static let touchingA = [
    "  case .utf8, .ascii:",
    "    return String(validating: bytes, as: Unicode.UTF8.self)",
  ]

  private static let touchingB = [
    "  case .utf16LittleEndian, .utf16:",
    "    return decode(bytes, as: Unicode.UTF16.self, bigEndian: false)",
  ]
}
