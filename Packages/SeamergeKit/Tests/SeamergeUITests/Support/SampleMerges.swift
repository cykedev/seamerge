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
}
