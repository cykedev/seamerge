import Foundation
import Testing

@testable import MergeModel

/// Patches written by ``UnifiedDiff`` and read back: the sides of each file show the changes of
/// the files they were written from, at the numbers of those files.
struct PatchFileTests {
  /// The lines and their numbers that a comparison finds changed.
  struct Changes: Equatable, CustomStringConvertible {
    var removed: [Int32] = []
    var added: [Int32] = []

    var description: String { "removed \(removed), added \(added)" }
  }

  @Test(arguments: PatchApplicationTests.changes)
  func sidesOfAWrittenPatchShowTheChangesOfItsFiles(
    change: PatchApplicationTests.Change
  ) async throws {
    let files = try PatchFile.files(in: UnifiedDiff.data(of: change.files))

    let paths = Set(change.old.keys).union(change.new.keys).sorted()
    #expect(files.map { $0.newPath ?? $0.oldPath } == paths)
    for (file, path) in zip(files, paths) {
      let old = SourceFile(bytes: change.old[path] ?? Data(), label: "old")
      let new = SourceFile(bytes: change.new[path] ?? Data(), label: "new")
      #expect(file.oldPath == (change.old[path] == nil ? nil : path))
      #expect(file.newPath == (change.new[path] == nil ? nil : path))
      try await Self.expectLines(
        of: file.old, toBeThoseOf: old, apartFrom: file.gaps.map(\.oldLine))
      try await Self.expectLines(
        of: file.new, toBeThoseOf: new, apartFrom: file.gaps.map(\.newLine))
      let original = try await Session.diff(old: old, new: new)
      #expect(try await Self.changes(of: file) == Self.changes(of: original), "\(path)")
    }
  }

  @Test func linesTheHunksPassOverStandAsOnePlaceholderOnEachSide() async throws {
    let old = Self.numberedText(1...100)
    let new = old.replacingOccurrences(of: "line 10\n", with: "ten\n")
      .replacingOccurrences(of: "line 50\n", with: "fifty\nfifty-one\n")
    let patch = try UnifiedDiff.data(of: [
      UnifiedDiff.File(old: .file(SourceFile(old)), new: .file(SourceFile(new)), names: .path("f"))
    ])

    let file = try #require(try PatchFile.files(in: patch).first)

    #expect(file.gaps.map(\.lineCount) == [6, 33])
    #expect(file.gaps.map(\.oldLine) == [0, 8])
    #expect(file.gaps.map(\.newLine) == [0, 8])
    let oldNumbers: [Int32] = [5] + Array(6...12) + [45] + Array(46...52)
    let newNumbers: [Int32] = [5] + Array(6...12) + [45] + Array(46...53)
    #expect(file.old.lineNumbers == oldNumbers)
    #expect(file.new.lineNumbers == newNumbers)
    let session = try await Self.session(of: file)
    #expect(session.gapRows.map { [$0.row, $0.lineCount] } == [[0, 6], [8, 33]])
    #expect(session.line(numbered: 46, in: .b) == 9)
    #expect(session.line(numbered: 30, in: .b) == 8)
    let collapsed = CollapsedRows(session: session)
    #expect(collapsed.runs.map(\.missingLineCount) == [6, 33])
    var expanded = collapsed
    let didExpand = expanded.expandToShow(row: 8)
    #expect(!didExpand)
    expanded.showAllRows()
    #expect(expanded.runs.map(\.rows) == [0..<1, 8..<9])
    #expect(try await Self.changes(of: file) == Changes(removed: [9, 49], added: [9, 49, 50]))
  }

  @Test func patchOfGitWithRenameModeChangeAndBinaryFileIsRead() async throws {
    let lines = (1...12).map { "line \($0)\n" }.joined()
    let trial = try PatchTrial(files: [
      "notes.txt": Data(lines.utf8), "run.sh": Data("echo hi\n".utf8),
      "logo.bin": Data([0x89, 0x50, 0x00, 0x01]),
    ])
    defer { trial.remove() }
    let identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
    #expect(try trial.git(["add", "-A"]).status == 0)
    #expect(try trial.git(identity + ["commit", "--quiet", "-m", "start"]).status == 0)
    let folder = trial.directory
    try FileManager.default.removeItem(at: folder.appending(path: "notes.txt"))
    try Data(lines.replacingOccurrences(of: "line 6\n", with: "six\n").utf8)
      .write(to: folder.appending(path: "renamed.txt"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "run.sh").path)
    try Data([0x89, 0x50, 0x00, 0x02]).write(to: folder.appending(path: "logo.bin"))
    #expect(try trial.git(["add", "-A"]).status == 0)
    let diff = try trial.git(["diff", "--cached", "-M"])
    try #require(diff.status == 0)
    try #require(diff.output.contains("rename from notes.txt"))
    try #require(diff.output.contains("new mode 100755"))

    let files = try PatchFile.files(in: Data(diff.output.utf8))

    #expect(files.map(\.newPath) == ["logo.bin", "renamed.txt"])
    #expect(files.map(\.oldPath) == ["logo.bin", "notes.txt"])
    #expect(files.map(\.isBinary) == [true, false])
    let renamed = files[1]
    #expect(try await Self.changes(of: renamed) == Changes(removed: [5], added: [5]))
  }

  /// With ten lines of context, the unchanged rows around a gap collapse on their own, each part
  /// keeping three rows of context beside the gap as beside a change.
  @Test func unchangedRowsAroundAGapCollapseApartFromIt() async throws {
    let context = (1...10).map { " c\($0)\n" }.joined()
    let text =
      "--- a\n+++ b\n@@ -1,11 +1,11 @@\n-a\n+b\n\(context)@@ -40,11 +40,11 @@\n\(context)-y\n+z\n"
    let file = try #require(try PatchFile.files(in: Data(text.utf8)).first)
    let session = try await Self.session(of: file)

    let collapsed = CollapsedRows(session: session)

    #expect(session.gapRows.map(\.row) == [11])
    #expect(collapsed.runs.map(\.rows) == [4..<8, 11..<12, 15..<19])
    #expect(collapsed.runs.map(\.missingLineCount) == [nil, 28, nil])
  }

  @Test func hunkAtTheStartOfTheFileHasNoGapBeforeItAndNoneFollowsTheLast() throws {
    let file = try #require(
      try PatchFile.files(in: Data("--- a\n+++ b\n@@ -1,2 +1,2 @@\n-a\n+b\n c\n".utf8)).first)

    #expect(file.gaps.isEmpty)
    #expect(file.old.text == "a\nc\n")
    #expect(file.new.text == "b\nc\n")
  }

  @Test func placeholderDiffersFromEveryLineOfTheFile() throws {
    let text = """
      --- a
      +++ b
      @@ -5,2 +5,2 @@
       \u{22EF}
      -\u{22EF}\u{22EF}\r
      +x\r

      """
    let file = try #require(try PatchFile.files(in: Data(text.utf8)).first)

    #expect(file.old.text == "\u{22EF}\u{22EF}\u{22EF}\n\u{22EF}\n\u{22EF}\u{22EF}\r\n")
    #expect(file.new.text == "\u{22EF}\u{22EF}\u{22EF}\n\u{22EF}\nx\r\n")
  }

  @Test func placeholderEndsAsTheFirstLineAfterIt() async throws {
    let first = try #require(
      try PatchFile.files(in: Data("--- a\n+++ b\n@@ -5 +5 @@\n-c\r\n+d\r\n".utf8)).first)
    #expect(first.old.text == "\u{22EF}\r\nc\r\n")
    #expect(first.new.text == "\u{22EF}\r\nd\r\n")

    let text = "--- a\n+++ b\n@@ -1 +1 @@\n-a\r\n+b\r\n@@ -9 +9 @@\n-c\r\n+d\r\n"
    let second = try #require(try PatchFile.files(in: Data(text.utf8)).first)
    #expect(second.old.text == "a\r\n\u{22EF}\r\nc\r\n")
  }

  /// A patch of `git diff -U0` that turns CRLF into LF: both placeholders end alike, so that the
  /// comparison pairs them and the bar stands.
  @Test func placeholdersOfAChangeOfLineEndingsAreTheSameOnBothSides() async throws {
    let text = "--- a\n+++ b\n@@ -1 +1 @@\n-a\r\n+a\n@@ -5 +5 @@\n-c\r\n+c\n"
    let file = try #require(try PatchFile.files(in: Data(text.utf8)).first)

    #expect(file.old.text == "a\r\n\u{22EF}\r\nc\r\n")
    #expect(file.new.text == "a\n\u{22EF}\r\nc\n")
    let session = try await Self.session(of: file)
    #expect(session.gapRows.map(\.lineCount) == [3])
  }

  @Test func linesOfAnotherEncodingAreDecodedInIt() throws {
    var bytes = Data("--- a\n+++ b\n@@ -1 +1 @@\n-gr".utf8)
    bytes.append(contentsOf: [0xF6, 0xDF, 0x65, 0x0A])
    bytes.append(contentsOf: Data("+gro".utf8))
    bytes.append(contentsOf: [0xDF, 0x0A])

    let file = try #require(try PatchFile.files(in: bytes).first)

    #expect(file.old.text == "größe\n")
    #expect(file.new.text == "groß\n")
  }

  @Test func binaryFileAndFileWithNulBytesHaveNoLines() throws {
    var bytes = Data("Binary files a/x and b/x differ\n--- a/y\n+++ b/y\n@@ -1 +1 @@\n-a".utf8)
    bytes.append(contentsOf: [0x00, 0x0A])
    bytes.append(contentsOf: Data("+b\n".utf8))

    let files = try PatchFile.files(in: bytes)

    #expect(files.map(\.isBinary) == [true, true])
    #expect(files.map(\.old.text) == ["", ""])
  }

  @Test func patchThatCannotBeReadSaysSo() {
    #expect(throws: MergeModelError.unreadablePatch) {
      try PatchFile.files(in: Data("--- a\n+++ b\n@@ -1,2 +1 @@\n-a\n".utf8))
    }
  }

  /// A patch of 60 000 lines is read in a fraction of the time a window may take to open; the
  /// time is printed with the test.
  @Test func largePatchIsReadInLinearTime() throws {
    let old = (1...40_000).map { "line \($0) of a large file\n" }.joined()
    let new = (1...40_000).map { $0 % 2 == 0 ? "changed \($0)\n" : "line \($0) of a large file\n" }
      .joined()
    let patch = try UnifiedDiff.data(of: [
      UnifiedDiff.File(old: .file(SourceFile(old)), new: .file(SourceFile(new)), names: .path("f"))
    ])
    let clock = ContinuousClock()
    let start = clock.now

    let files = try PatchFile.files(in: patch)

    let time = clock.now - start
    print("A patch of \(patch.count) bytes reads in \(time)")
    #expect(files.first?.new.lineNumbers.count == 40_000)
    #expect(time < .seconds(5))
  }

  /// The sides of a patch and its collapsed runs take linear time.
  ///
  /// Four times the hunks take well under eight times as long, where quadratic time would take
  /// sixteen. A ratio rather than a fixed limit holds under the sanitizers too; the times are
  /// printed with the test.
  @Test func manyHunksMakeSidesAndRunsInLinearTime() async throws {
    let small = try await Self.timeSidesAndRuns(hunks: 10_000)
    let large = try await Self.timeSidesAndRuns(hunks: 40_000)

    print("10 000 hunks: sides \(small.sides), runs \(small.runs)")
    print("40 000 hunks: sides \(large.sides), runs \(large.runs)")
    #expect(large.sides < small.sides * 8)
    #expect(large.runs < small.runs * 8)
  }

  /// Files of random lines with random changes, written as a patch and read back; seed 60.
  @Test func randomChangesReadBackAsTheyWereWritten() async throws {
    var generator = SplitMix64(seed: 60)
    let words = ["a", "b", "c", "", "{", "}", "return x", "\u{22EF}"]
    for round in 0..<60 {
      let lines = (0..<Int.random(in: 0...80, using: &generator)).map { _ in
        words.randomElement(using: &generator) ?? ""
      }
      var changed = lines
      for _ in 0..<Int.random(in: 0...6, using: &generator) {
        let index = Int.random(in: 0...changed.count, using: &generator)
        if index < changed.count && Bool.random(using: &generator) {
          changed.remove(at: index)
        } else {
          changed.insert("new \(round)", at: index)
        }
      }
      let old = SourceFile(lines.map { $0 + "\n" }.joined())
      let new = SourceFile(changed.map { $0 + "\n" }.joined())
      let patch = try UnifiedDiff.data(of: [
        UnifiedDiff.File(old: .file(old), new: .file(new), names: .path("f"))
      ])
      let files = try PatchFile.files(in: patch)
      guard let file = files.first else {
        #expect(old.bytes == new.bytes, "round \(round)")
        continue
      }
      try await Self.expectLines(
        of: file.old, toBeThoseOf: old, apartFrom: file.gaps.map(\.oldLine))
      try await Self.expectLines(
        of: file.new, toBeThoseOf: new, apartFrom: file.gaps.map(\.newLine))
      let original = try await Session.diff(old: old, new: new)
      #expect(try await Self.changes(of: file) == Self.changes(of: original), "round \(round)")
    }
  }

  /// Expects each line of `side` as a comparison splits it, apart from the placeholder lines
  /// `placeholders`, to read as the line of `file` whose number it has.
  private static func expectLines(
    of side: PatchFile.Side, toBeThoseOf file: SourceFile, apartFrom placeholders: [Int]
  ) async throws {
    let session = try await Session.diff(
      old: SourceFile(side.text).holding(side), new: SourceFile(""))
    let numbers = try #require(session.lineNumbers(in: .a))
    let original = lines(of: try #require(file.text))
    let shown = lines(of: side.text)
    #expect(shown.count == numbers.count)
    for (index, (line, number)) in zip(shown, numbers).enumerated()
    where !placeholders.contains(index) {
      #expect(line == original[Int(number)])
    }
  }

  /// The lines of `text` with their line endings, split at line feeds, or at carriage returns in
  /// a text without line feeds, as a comparison splits them.
  private static func lines(of text: String) -> [String] {
    let scalars = text.unicodeScalars
    let separator: Unicode.Scalar = scalars.contains("\n") || !scalars.contains("\r") ? "\n" : "\r"
    var lines: [String] = []
    var line = String.UnicodeScalarView()
    for scalar in scalars {
      line.append(scalar)
      if scalar == separator {
        lines.append(String(line))
        line = String.UnicodeScalarView()
      }
    }
    if !line.isEmpty { lines.append(String(line)) }
    return lines
  }

  /// The changed lines of the comparison of the sides of `file`, at their numbers in the files.
  private static func changes(of file: PatchFile) async throws -> Changes {
    let session = try await Self.session(of: file)
    let (old, new) = (
      try #require(session.lineNumbers(in: .a)), try #require(session.lineNumbers(in: .b))
    )
    var changes = Changes()
    for block in session.blocks where block.kind != .unchanged {
      changes.removed += block.a.map { old[$0] }
      changes.added += block.b.map { new[$0] }
    }
    return Changes(removed: changes.removed.sorted(), added: changes.added.sorted())
  }

  /// Times the sides of a patch of `hunks` one-line hunks and their collapsed runs, and checks
  /// that every gap between two hunks became a gap row and a run.
  private static func timeSidesAndRuns(
    hunks: Int
  ) async throws -> (sides: Duration, runs: Duration) {
    var text = "diff --git a/f b/f\n--- a/f\n+++ b/f\n"
    for hunk in 0..<hunks {
      text += "@@ -\(hunk * 10 + 1) +\(hunk * 10 + 1) @@\n-old \(hunk)\n+new \(hunk)\n"
    }
    let clock = ContinuousClock()
    var start = clock.now
    let file = try #require(try PatchFile.files(in: Data(text.utf8)).first)
    let sides = clock.now - start
    let session = try await session(of: file)
    start = clock.now
    let collapsed = CollapsedRows(session: session)
    let runs = clock.now - start

    #expect(session.gapRows.count == hunks - 1)
    #expect(collapsed.runs.count == hunks - 1)
    return (sides, runs)
  }

  /// The comparison of the sides of `file`, each held by the file it is read from.
  private static func session(of file: PatchFile) async throws -> Session {
    try await Session.diff(
      old: SourceFile(file.old.text).holding(file.old),
      new: SourceFile(file.new.text).holding(file.new))
  }

  private static func changes(of session: Session) -> Changes {
    var changes = Changes()
    for block in session.blocks where block.kind != .unchanged {
      changes.removed += block.a.map { Int32($0) }
      changes.added += block.b.map { Int32($0) }
    }
    return Changes(removed: changes.removed.sorted(), added: changes.added.sorted())
  }

  private static func numberedText(_ numbers: ClosedRange<Int>) -> String {
    numbers.map { "line \($0)\n" }.joined()
  }
}
