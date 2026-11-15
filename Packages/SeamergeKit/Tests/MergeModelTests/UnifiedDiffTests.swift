import Foundation
import MergeModel
import Testing

struct UnifiedDiffTests {
  @Test func changedFileHasTheHeadersOfGitAndThreeLinesOfContext() throws {
    let patch = try Self.patch(
      path: "notes.txt", old: "1\n2\n3\n4\n5\n6\n7\n8\n9\n", new: "1\n2\n3\n4\nfive\n6\n7\n8\n9\n")

    #expect(
      patch == """
        diff --git a/notes.txt b/notes.txt
        --- a/notes.txt
        +++ b/notes.txt
        @@ -2,7 +2,7 @@
         2
         3
         4
        -5
        +five
         6
         7
         8

        """)
  }

  @Test func changesThatSixUnchangedLinesPartShareAHunk() throws {
    let old = Self.numberedLines(1...20)
    let new = old.replacingOccurrences(of: "l2\n", with: "two\n")
      .replacingOccurrences(of: "l9\n", with: "nine\n")

    let patch = try Self.patch(path: "f", old: old, new: new)

    #expect(Self.hunkHeaders(of: patch) == ["@@ -1,12 +1,12 @@"])
  }

  @Test func changesThatSevenUnchangedLinesPartTakeAHunkEach() throws {
    let old = Self.numberedLines(1...20)
    let new = old.replacingOccurrences(of: "l2\n", with: "two\n")
      .replacingOccurrences(of: "l10\n", with: "ten\n")

    let patch = try Self.patch(path: "f", old: old, new: new)

    #expect(Self.hunkHeaders(of: patch) == ["@@ -1,5 +1,5 @@", "@@ -7,7 +7,7 @@"])
  }

  @Test func insertionAndRemovalCountFromTheLineBeforeThem() throws {
    let inserted = try Self.patch(path: "f", old: "a\nb\n", new: "a\nnew\nb\n")
    let removed = try Self.patch(path: "f", old: "a\nb\n", new: "b\n")

    #expect(Self.hunkHeaders(of: inserted) == ["@@ -1,2 +1,3 @@"])
    #expect(Self.hunkHeaders(of: removed) == ["@@ -1,2 +1 @@"])
  }

  @Test func lastLinesWithoutALineBreakAreMarkedAsGitMarksThem() throws {
    let patch = try Self.patch(path: "f", old: "a\nb", new: "a\nc")

    #expect(
      patch.hasSuffix(
        """
        @@ -1,2 +1,2 @@
         a
        -b
        \\ No newline at end of file
        +c
        \\ No newline at end of file

        """))
  }

  @Test func lastLineThatGainsALineBreakIsAChange() throws {
    let patch = try Self.patch(path: "f", old: "a\nb", new: "a\nb\n")

    #expect(
      patch.hasSuffix(
        """
        -b
        \\ No newline at end of file
        +b

        """))
  }

  @Test func newFileLeadsFromDevNullWithTheModeGitNeedsForIt() throws {
    let files = [
      UnifiedDiff.File(old: .missing, new: .file(SourceFile("a\nb\n")), names: .path("new.txt"))
    ]

    #expect(
      try Self.string(UnifiedDiff.data(of: files)) == """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +a
        +b

        """)
  }

  @Test func deletedFileLeadsToDevNullWithTheModeGitNeedsForIt() throws {
    let files = [
      UnifiedDiff.File(old: .file(SourceFile("a\nb\n")), new: .missing, names: .path("old.txt"))
    ]

    #expect(
      try Self.string(UnifiedDiff.data(of: files)) == """
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        --- a/old.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -a
        -b

        """)
  }

  @Test func newEmptyFileHasOnlyItsHeaders() throws {
    let files = [
      UnifiedDiff.File(old: .missing, new: .file(SourceFile("")), names: .path("empty"))
    ]

    #expect(
      try Self.string(UnifiedDiff.data(of: files)) == """
        diff --git a/empty b/empty
        new file mode 100644

        """)
  }

  @Test func emptyFileThatIsNewOrDeletedWithoutAPathIsNoChange() throws {
    let empty = SourceFile("")
    let files = [
      UnifiedDiff.File(
        old: .missing, new: .file(empty), names: .labels(old: "/dev/null", new: "empty.txt")),
      UnifiedDiff.File(
        old: .file(empty), new: .missing, names: .labels(old: "empty.txt", new: "/dev/null")),
    ]

    #expect(files.allSatisfy { !$0.hasChanges })
    #expect(try UnifiedDiff.data(of: files).isEmpty)
    #expect(UnifiedDiff.File(old: .missing, new: .file(empty), names: .path("empty")).hasChanges)
  }

  @Test func sidesWithoutAPathAreNamedByTheirLabels() throws {
    let files = [
      UnifiedDiff.File(
        old: .file(SourceFile("a\n")), new: .file(SourceFile("b\n")),
        names: .labels(old: "draft.txt", new: "final copy.txt"))
    ]

    #expect(
      try Self.string(UnifiedDiff.data(of: files)) == """
        --- draft.txt
        +++ final copy.txt\t
        @@ -1 +1 @@
        -a
        +b

        """)
  }

  @Test func pathWithASpaceEndsWithATabInTheLinesOfTheSides() throws {
    let patch = try Self.patch(path: "My Notes/to do.txt", old: "a\n", new: "b\n")

    #expect(
      patch.hasPrefix(
        """
        diff --git a/My Notes/to do.txt b/My Notes/to do.txt
        --- a/My Notes/to do.txt\t
        +++ b/My Notes/to do.txt\t

        """))
  }

  @Test(arguments: [
    ("say \"hi\".txt", #""a/say \"hi\".txt""#),
    ("back\\slash", #""a/back\\slash""#),
    ("tab\there", #""a/tab\there""#),
    ("Größe.txt", #""a/Gr\303\266\303\237e.txt""#),
    ("plain-name_1.txt", "a/plain-name_1.txt"),
  ])
  func pathsAreQuotedAsGitQuotesThem(path: String, quoted: String) throws {
    let patch = try Self.patch(path: path, old: "a\n", new: "b\n")

    let sides = patch.split(separator: "\n").dropFirst().first ?? ""
    #expect(sides == "--- \(quoted)" || sides == "--- \(quoted)\t")
  }

  @Test func filesWithTheSameBytesAreLeftOut() throws {
    let same = UnifiedDiff.File(
      old: .file(SourceFile("a\n")), new: .file(SourceFile("a\n")), names: .path("same"))
    let changed = UnifiedDiff.File(
      old: .file(SourceFile("a\n")), new: .file(SourceFile("b\n")), names: .path("changed"))

    #expect(!same.hasChanges)
    #expect(try UnifiedDiff.data(of: [same]).isEmpty)
    #expect(
      try Self.string(UnifiedDiff.data(of: [same, changed])).hasPrefix("diff --git a/changed"))
  }

  @Test func whitespaceAndLineEndingsCount() throws {
    let patch = try Self.patch(path: "f", old: "a b\nc\r\n", new: "a  b\nc\n")

    #expect(patch.hasSuffix("-a b\n-c\r\n+a  b\n+c\n"))
  }

  @Test func linesKeepTheBytesOfTheirFile() throws {
    let old = Data([0xEF, 0xBB, 0xBF]) + Data("keep\r\nold\r\n".utf8)
    let new = Data([0xEF, 0xBB, 0xBF]) + Data("keep\r\nnew\r\n".utf8)
    let files = [
      UnifiedDiff.File(
        old: .file(SourceFile(bytes: old, label: "old")),
        new: .file(SourceFile(bytes: new, label: "new")), names: .path("f"))
    ]

    let data = try UnifiedDiff.data(of: files)

    #expect(
      data.ends(with: Data([0x20, 0xEF, 0xBB, 0xBF]) + Data("keep\r\n-old\r\n+new\r\n".utf8)))
  }

  @Test func fileWhoseLinesEndInCarriageReturnsIsOneLine() throws {
    let patch = try Self.patch(path: "f", old: "a\rb\r", new: "a\rc\r")

    #expect(
      patch.hasSuffix(
        "@@ -1 +1 @@\n-a\rb\r\n\\ No newline at end of file\n+a\rc\r\n\\ No newline at end of file\n"
      ))
  }

  @Test func bytesOfAnotherEncodingStayInTheDataAndDecodeInTheText() throws {
    let old = Data("Gr".utf8) + Data([0xF6, 0xDF]) + Data("e\n".utf8)
    let new = Data("Gr".utf8) + Data([0xD6, 0xDF]) + Data("E\n".utf8)
    let files = [
      UnifiedDiff.File(
        old: .file(SourceFile(bytes: old, label: "old")),
        new: .file(SourceFile(bytes: new, label: "new")), names: .path("latin1.txt"))
    ]
    try #require(SourceFile(bytes: old, label: "old").encoding == .isoLatin1)

    let data = try UnifiedDiff.data(of: files)
    let text = try UnifiedDiff.text(of: files)

    #expect(data.ends(with: Data("-".utf8) + old + Data("+".utf8) + new))
    #expect(text.hasSuffix("-Größe\n+GrÖßE\n"))
  }

  @Test func textOfFilesInUTF8IsTheirData() throws {
    let files = [
      UnifiedDiff.File(
        old: .file(SourceFile("Größe\n")), new: .file(SourceFile("Grösse\n")),
        names: .path("Größe.txt")),
      UnifiedDiff.File(old: .missing, new: .file(SourceFile("neu\n")), names: .path("neu.txt")),
    ]

    #expect(try Data(UnifiedDiff.text(of: files).utf8) == UnifiedDiff.data(of: files))
  }

  @Test func filesWhoseLinesCannotBeShownSayOnlyThatTheyDiffer() throws {
    let utf16 = SourceFile(bytes: Data([0xFF, 0xFE, 0x61, 0x00, 0x0A, 0x00]), label: "utf16")
    let binary = SourceFile(bytes: Data([0x00, 0x01, 0x02]), label: "binary")
    let files = [
      UnifiedDiff.File(old: .file(SourceFile("a\n")), new: .file(utf16), names: .path("wide.txt")),
      UnifiedDiff.File(old: .missing, new: .file(binary), names: .path("image.png")),
      UnifiedDiff.File(old: .unreadable, new: .file(SourceFile("a\n")), names: .path("locked")),
      UnifiedDiff.File(
        old: .file(binary), new: .missing, names: .labels(old: "left.bin", new: "right.bin")),
    ]

    #expect(files.allSatisfy { !$0.showsLines && $0.hasChanges })
    #expect(
      try Self.string(UnifiedDiff.data(of: files)) == """
        diff --git a/wide.txt b/wide.txt
        Binary files a/wide.txt and b/wide.txt differ
        diff --git a/image.png b/image.png
        new file mode 100644
        Binary files /dev/null and b/image.png differ
        diff --git a/locked b/locked
        Binary files a/locked and b/locked differ
        Binary files left.bin and /dev/null differ

        """)
  }

  @Test func filesFollowEachOtherInTheirOrder() throws {
    let files = ["c", "a", "b"].map { path in
      UnifiedDiff.File(
        old: .file(SourceFile("\(path)\n")), new: .file(SourceFile("\(path)!\n")),
        names: .path(path))
    }

    let headers = try Self.string(UnifiedDiff.data(of: files)).split(separator: "\n")
      .filter { $0.hasPrefix("diff --git") }

    #expect(headers == ["diff --git a/c b/c", "diff --git a/a b/a", "diff --git a/b b/b"])
  }

  /// The patch of the file at `path` from `old` to `new`, as UTF-8 text.
  private static func patch(path: String, old: String, new: String) throws -> String {
    try string(
      UnifiedDiff.data(of: [
        UnifiedDiff.File(
          old: .file(SourceFile(old)), new: .file(SourceFile(new)), names: .path(path))
      ]))
  }

  private static func string(_ data: Data) throws -> String {
    try #require(String(data: data, encoding: .utf8))
  }

  private static func numberedLines(_ numbers: ClosedRange<Int>) -> String {
    numbers.map { "l\($0)\n" }.joined()
  }

  private static func hunkHeaders(of patch: String) -> [Substring] {
    patch.split(separator: "\n").filter { $0.hasPrefix("@@") }
  }
}

extension Data {
  fileprivate func ends(with suffix: Data) -> Bool {
    count >= suffix.count && self.suffix(suffix.count) == suffix
  }
}
