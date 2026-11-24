import Foundation
import Testing
import TextIO

struct PatchReadingTests {
  private func read(_ text: String) throws -> Patch {
    try Patch(reading: Data(text.utf8))
  }

  /// The lines of `hunk` as the patch writes them: sign and bytes.
  private func lines(of hunk: Patch.Hunk, in patch: Patch) -> [String] {
    hunk.lines.map { line in
      let sign =
        switch line.kind {
        case .context: " "
        case .removed: "-"
        case .added: "+"
        }
      return sign + String(decoding: patch.content(of: line), as: UTF8.self)
    }
  }

  @Test func changedFileOfGitDiffHasItsPathsRangesAndLines() throws {
    let patch = try read(
      """
      diff --git a/Sources/main.swift b/Sources/main.swift
      index 3b18e51..a2c4f0d 100644
      --- a/Sources/main.swift
      +++ b/Sources/main.swift
      @@ -2,3 +2,4 @@ func main() {
       let a = 1
      -let b = 2
      +let b = 3
      +let c = 4
       print(a)

      """)

    let file = try #require(patch.files.first)
    #expect(patch.files.count == 1)
    #expect(file.oldPath == "Sources/main.swift")
    #expect(file.newPath == "Sources/main.swift")
    #expect(!file.isBinary)
    let hunk = try #require(file.hunks.first)
    #expect(hunk.old == Patch.LineRange(start: 2, count: 3))
    #expect(hunk.new == Patch.LineRange(start: 2, count: 4))
    #expect(hunk.old.lines == 1..<4)
    #expect(
      lines(of: hunk, in: patch) == [
        " let a = 1\n", "-let b = 2\n", "+let b = 3\n", "+let c = 4\n", " print(a)\n",
      ])
  }

  @Test func newAndDeletedFilesHaveNoPathOnTheMissingSide() throws {
    let patch = try read(
      """
      diff --git a/new.txt b/new.txt
      new file mode 100644
      index 0000000..ce01362
      --- /dev/null
      +++ b/new.txt
      @@ -0,0 +1 @@
      +hello
      diff --git a/old.txt b/old.txt
      deleted file mode 100644
      index ce01362..0000000
      --- a/old.txt
      +++ /dev/null
      @@ -1 +0,0 @@
      -hello

      """)

    #expect(patch.files.map(\.oldPath) == [nil, "old.txt"])
    #expect(patch.files.map(\.newPath) == ["new.txt", nil])
    #expect(patch.files[0].hunks[0].old.lines == 0..<0)
    #expect(patch.files[0].hunks[0].new.lines == 0..<1)
  }

  @Test func emptyNewFileWithoutHunksStillCounts() throws {
    let patch = try read(
      """
      diff --git a/empty.txt b/empty.txt
      new file mode 100644
      index 0000000..e69de29

      """)

    #expect(patch.files == [Patch.File(oldPath: nil, newPath: "empty.txt")])
  }

  @Test func renameNamesBothSidesWithOrWithoutChanges() throws {
    let patch = try read(
      """
      diff --git a/before.txt b/after.txt
      similarity index 100%
      rename from before.txt
      rename to after.txt
      diff --git "a/dir/\\303\\244lt.txt" "b/dir/neu.txt"
      similarity index 80%
      rename from "dir/\\303\\244lt.txt"
      rename to dir/neu.txt
      index 1111111..2222222 100644
      --- "a/dir/\\303\\244lt.txt"
      +++ b/dir/neu.txt
      @@ -1 +1 @@
      -a
      +b

      """)

    #expect(patch.files.map(\.oldPath) == ["before.txt", "dir/ält.txt"])
    #expect(patch.files.map(\.newPath) == ["after.txt", "dir/neu.txt"])
    #expect(patch.files[0].hunks.isEmpty)
    #expect(patch.files[1].hunks.count == 1)
  }

  @Test func fileWhoseModeAloneChangesIsLeftOutButCountsAsNamed() throws {
    let patch = try read(
      """
      diff --git a/run.sh b/run.sh
      old mode 100644
      new mode 100755

      """)

    #expect(patch.files.isEmpty)
  }

  @Test func modeChangeBesideChangedLinesIsPassedOver() throws {
    let patch = try read(
      """
      diff --git a/run.sh b/run.sh
      old mode 100644
      new mode 100755
      index 1111111..2222222
      --- a/run.sh
      +++ b/run.sh
      @@ -1 +1 @@
      -echo a
      +echo b

      """)

    #expect(patch.files.count == 1)
    #expect(patch.files[0].hunks[0].lines.map(\.kind) == [.removed, .added])
  }

  @Test func binaryFilesOfGitAndOfDiffSayOnlyThatTheyDiffer() throws {
    let patch = try read(
      """
      diff --git a/image.png b/image.png
      index 1111111..2222222 100644
      Binary files a/image.png and b/image.png differ
      diff --git a/icon.png b/icon.png
      new file mode 100644
      index 0000000..3333333
      GIT binary patch
      literal 5
      McmZQzWMXE(000310RR91

      literal 0
      HcmV?d00001

      Binary files left/data.bin and right/data.bin differ

      """)

    #expect(patch.files.map(\.isBinary) == [true, true, true])
    #expect(patch.files.map(\.oldPath) == ["image.png", nil, "left/data.bin"])
    #expect(patch.files.map(\.newPath) == ["image.png", "icon.png", "right/data.bin"])
  }

  @Test func lineWithoutLineFeedAtTheEndOfAFileLosesIt() throws {
    let patch = try read(
      """
      --- a.txt
      +++ b.txt
      @@ -1,2 +1,3 @@
       one
      -two
      \\ No newline at end of file
      +two
      +three
      \\ No newline at end of file

      """)

    #expect(
      lines(of: patch.files[0].hunks[0], in: patch) == [" one\n", "-two", "+two\n", "+three"])
  }

  @Test func countsOfTheHeaderDecideLinesThatLookLikeHeaders() throws {
    let patch = try read(
      """
      --- a.sql
      +++ b.sql
      @@ -1,2 +1,2 @@
      --- a comment
      +++ another comment
      -select 1;
      +select 2;

      """)

    #expect(
      lines(of: patch.files[0].hunks[0], in: patch) == [
        "--- a comment\n", "+++ another comment\n", "-select 1;\n", "+select 2;\n",
      ])
  }

  @Test func carriageReturnsStayInTheLines() throws {
    let patch = try read("--- a\n+++ b\n@@ -1,2 +1,2 @@\n same\r\n-old\r\n+new\r\n")

    #expect(lines(of: patch.files[0].hunks[0], in: patch) == [" same\r\n", "-old\r\n", "+new\r\n"])
  }

  @Test func headersOfAPatchWithCarriageReturnsAreRead() throws {
    let patch = try read("--- a/x.txt\r\n+++ b/x.txt\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n")

    #expect(patch.files.map(\.oldPath) == ["x.txt"])
    #expect(lines(of: patch.files[0].hunks[0], in: patch) == ["-a\r\n", "+b\r\n"])
  }

  @Test func pathsAreUnquotedAsGitQuotesThem() throws {
    let patch = try read(
      """
      diff --git "a/sp\\303\\244ter \\"x\\".txt" "b/sp\\303\\244ter \\"x\\".txt"
      --- "a/sp\\303\\244ter \\"x\\".txt"
      +++ "b/sp\\303\\244ter \\"x\\".txt"
      @@ -1 +1 @@
      -a
      +b
      diff --git a/with space.txt b/with space.txt
      --- a/with space.txt\t
      +++ b/with space.txt\t
      @@ -1 +1 @@
      -a
      +b

      """)

    #expect(patch.files.map(\.newPath) == ["später \"x\".txt", "with space.txt"])
  }

  @Test func namesOfTheLineOfGitAloneMayHoldSpaces() throws {
    let patch = try read(
      """
      diff --git a/a b/c.txt b/a b/c.txt
      new file mode 100644
      index 0000000..e69de29

      """)

    #expect(patch.files.map(\.newPath) == ["a b/c.txt"])
  }

  /// A line `diff --git` without quotes is split in linear time: the names of a file that keeps
  /// its name meet in the middle.
  ///
  /// Four times the length takes well under eight times as long, where quadratic time would take
  /// sixteen. A ratio rather than a fixed limit holds under the sanitizers too.
  @Test func longLineOfGitWithSpacesIsSplitInLinearTime() throws {
    func time(repeats: Int) throws -> Duration {
      let name = String(repeating: "a ", count: repeats) + "x"
      let text = "diff --git a/\(name) b/\(name)\nnew file mode 100644\n"
      let clock = ContinuousClock()
      let start = clock.now
      let patch = try read(text + "diff --git a/one two b/three\nnew file mode 100644\n")
      let time = clock.now - start
      #expect(patch.files.map(\.newPath) == [name, "three"])
      return time
    }
    let short = try time(repeats: 62_500)
    let long = try time(repeats: 250_000)

    print("A line of \(62_500) spaces splits in \(short), of \(250_000) in \(long)")
    #expect(long < short * 8)
  }

  @Test(arguments: [("i", "w"), ("c", "w"), ("c", "i"), ("o", "w"), ("1", "2")])
  func mnemonicPrefixesOfGitAreTakenOff(old: String, new: String) throws {
    let patch = try read(
      """
      diff --git \(old)/Sources/a.txt \(new)/Sources/a.txt
      --- \(old)/Sources/a.txt
      +++ \(new)/Sources/a.txt
      @@ -1 +1 @@
      -a
      +b
      diff --git \(old)/new.txt \(new)/new.txt
      new file mode 100644
      index 0000000..e69de29

      """)

    #expect(patch.files.map(\.oldPath) == ["Sources/a.txt", nil])
    #expect(patch.files.map(\.newPath) == ["Sources/a.txt", "new.txt"])
  }

  @Test func quotedNameThatDoesNotCloseCannotBeRead() {
    #expect(throws: PatchReadingError.malformedFileName(line: 1)) {
      try read("--- \"a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n")
    }
  }

  @Test func filesOfDiffKeepTheirNamesWithoutDates() throws {
    let patch = try read(
      """
      --- old/config.yml\t2026-11-24 10:00:00.000000000 +0100
      +++ new/config.yml\t2026-11-24 10:05:00.000000000 +0100
      @@ -1 +1 @@
      -a: 1
      +a: 2
      --- /dev/null\t1970-01-01 01:00:00.000000000 +0100
      +++ new/added.yml\t2026-11-24 10:05:00.000000000 +0100
      @@ -0,0 +1 @@
      +b: 1

      """)

    #expect(patch.files.map(\.oldPath) == ["old/config.yml", nil])
    #expect(patch.files.map(\.newPath) == ["new/config.yml", "new/added.yml"])
  }

  @Test func labelsOfTheExportKeepTheirPrefixesUnlessBothHaveThem() throws {
    let patch = try read(
      "--- a/x\n+++ c/x\n@@ -1 +1 @@\n-a\n+b\n--- a/y\n+++ b/y\n@@ -1 +1 @@\n-a\n+b\n")

    #expect(patch.files.map(\.oldPath) == ["a/x", "y"])
    #expect(patch.files.map(\.newPath) == ["c/x", "y"])
  }

  @Test func hunkHeadersWithoutLengthsCountOneLine() throws {
    let patch = try read("--- a\n+++ b\n@@ -7 +7,2 @@\n-x\n+y\n+z\n")

    #expect(patch.files[0].hunks[0].old == Patch.LineRange(start: 7, count: 1))
    #expect(patch.files[0].hunks[0].new == Patch.LineRange(start: 7, count: 2))
  }

  @Test func emptyLineOfContextWithoutItsSpaceCounts() throws {
    let patch = try read("--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n")

    #expect(lines(of: patch.files[0].hunks[0], in: patch) == [" a\n", " \n", "-b\n", "+c\n"])
  }

  @Test func messageAndSignatureOfFormatPatchArePassedOver() throws {
    let patch = try read(
      """
      From 1234567 Mon Sep 17 00:00:00 2001
      From: Someone <someone@example.com>
      Subject: [PATCH] Change a

      ---
       a.txt | 2 +-
       1 file changed, 1 insertion(+), 1 deletion(-)

      diff --git a/a.txt b/a.txt
      index 1111111..2222222 100644
      --- a/a.txt
      +++ b/a.txt
      @@ -1 +1 @@
      -a
      +b
      --\u{20}
      2.56.0


      """)

    #expect(patch.files.count == 1)
    #expect(patch.files[0].hunks[0].lines.count == 2)
  }

  @Test func combinedDiffCannotBeRead() {
    #expect(throws: PatchReadingError.combinedDiff(line: 1)) {
      try read("diff --cc file.txt\nindex 1,2..3\n--- a/file.txt\n+++ b/file.txt\n")
    }
    #expect(throws: PatchReadingError.combinedDiff(line: 3)) {
      try read("--- a/file.txt\n+++ b/file.txt\n@@@ -1,1 -1,1 +1,1 @@@\n")
    }
  }

  @Test func hunkCutOffAtTheEndIsTruncated() {
    #expect(throws: PatchReadingError.truncatedHunk(line: 3)) {
      try read("--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n")
    }
  }

  @Test func hunkCutOffByTheNextFileIsTruncated() {
    #expect(throws: PatchReadingError.truncatedHunk(line: 3)) {
      try read("--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n+c\ndiff --git a/x b/x\n")
    }
  }

  @Test func lineBeyondTheCountsOfTheHeaderIsAMismatch() {
    #expect(throws: PatchReadingError.hunkLengthMismatch(line: 3)) {
      try read("--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n+c\n")
    }
    #expect(throws: PatchReadingError.hunkLengthMismatch(line: 3)) {
      try read("--- a\n+++ b\n@@ -1,2 +1 @@\n-a\n+b\n+c\n")
    }
  }

  @Test func hunkBeforeItsFileCannotBeRead() {
    #expect(throws: PatchReadingError.hunkWithoutFile(line: 2)) {
      try read("diff --git a/x b/x\n@@ -1 +1 @@\n-a\n+b\n")
    }
  }

  @Test(arguments: ["@@ -a +1 @@", "@@ -1 +1", "@@ -0,1 +1 @@", "@@ -1 +1234567890 @@"])
  func malformedHunkHeaderCannotBeRead(header: String) {
    #expect(throws: PatchReadingError.malformedHunkHeader(line: 3)) {
      try read("--- a\n+++ b\n\(header)\n-a\n+b\n")
    }
  }

  @Test(arguments: [
    "*** a.txt\n--- b.txt\n***************\n*** 1 ****\n! a\n--- 1 ----\n! b\n",
    "1c1\n< a\n---\n> b\n",
    "just some text\n",
  ])
  func otherFormatsAreNoUnifiedDiff(text: String) {
    #expect(throws: PatchReadingError.notUnifiedDiff) { try read(text) }
  }

  @Test(arguments: ["", "\n", "  \n\t\r\n"])
  func emptyTextIsAPatchWithoutFiles(text: String) throws {
    let patch = try read(text)

    #expect(patch.files.isEmpty)
  }

  @Test func bytesOutsideUTF8StayInTheLines() throws {
    var bytes = Data("--- a\n+++ b\n@@ -1 +1 @@\n-".utf8)
    bytes.append(contentsOf: [0xE4, 0x0A])
    bytes.append(contentsOf: Data("+\u{E4}\n".utf8))

    let patch = try Patch(reading: bytes)

    let removed = try #require(patch.files.first?.hunks.first?.lines.first)
    #expect(patch.content(of: removed) == Data([0xE4, 0x0A]))
  }

  @Test func sliceOfLargerDataReadsAsItsOwnBytes() throws {
    let whole = Data("xx--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n".utf8)

    let patch = try Patch(reading: whole.dropFirst(2))

    #expect(patch.files.count == 1)
    let added = try #require(patch.files.first?.hunks.first?.lines.last)
    #expect(patch.content(of: added) == Data("b\n".utf8))
  }

  /// A patch of 60 000 lines is read in linear time; the time is printed with the test.
  @Test func largePatchIsReadInLinearTime() throws {
    var text = "--- a/f\n+++ b/f\n@@ -1,40000 +1,40000 @@\n"
    for line in 1...40_000 {
      text += line % 2 == 0 ? "-line \(line)\n+changed \(line)\n" : " line \(line)\n"
    }
    let clock = ContinuousClock()
    let start = clock.now

    let patch = try read(text)

    let time = clock.now - start
    print("A patch of \(text.utf8.count) bytes reads in \(time)")
    #expect(patch.files.first?.hunks.first?.lines.count == 60_000)
    #expect(time < .seconds(5))
  }

  /// A patch of 40 000 hunks, as `git diff -U0` writes for a large file changed here and
  /// there, is read in linear time; the times are printed with the test.
  @Test func manyHunksAreReadInLinearTime() throws {
    func patch(hunks: Int) -> String {
      var text = "diff --git a/f b/f\n--- a/f\n+++ b/f\n"
      for hunk in 0..<hunks {
        text += "@@ -\(hunk * 10 + 1) +\(hunk * 10 + 1) @@\n-old \(hunk)\n+new \(hunk)\n"
      }
      return text
    }
    let clock = ContinuousClock()
    var times: [Duration] = []
    for hunks in [20_000, 40_000] {
      let text = patch(hunks: hunks)
      let start = clock.now
      let read = try read(text)
      times.append(clock.now - start)
      #expect(read.files.first?.hunks.count == hunks)
    }
    print("20 000 hunks read in \(times[0]), 40 000 in \(times[1])")
    // Twice the hunks take well under three times as long, where quadratic time would take
    // four; a ratio holds under the sanitizers too.
    #expect(times[1] < times[0] * 3)
  }

  /// Mutates a patch at random and reads it, so that no input crashes the reader or keeps it
  /// from ending; seed 60, printed by the test name.
  @Test func randomlyDamagedPatchesNeitherCrashNorHang() {
    let sample = Array(
      """
      diff --git "a/x \\303\\244" b/y
      rename from x
      rename to y
      --- a/x\t2026
      +++ b/y
      @@ -1,3 +1,4 @@ section
       a
      -b
      +c
      +d
      \\ No newline at end of file
       e
      @@ -9 +10,0 @@
      -f
      Binary files a/z and b/z differ

      """.utf8)
    let alphabet = Array(" -+@\\\n\r\t\",0123456789abdfgit/".utf8)
    var generator = SplitMix64(seed: 60)
    var (readCount, refusedCount) = (0, 0)
    for _ in 0..<5000 {
      var bytes = sample
      for _ in 0..<Int.random(in: 1...6, using: &generator) {
        let index = Int.random(in: 0...bytes.count, using: &generator)
        switch Int.random(in: 0..<3, using: &generator) {
        case 0 where index < bytes.count: bytes.remove(at: index)
        case 1 where index < bytes.count:
          bytes[index] = alphabet.randomElement(using: &generator) ?? 0
        default: bytes.insert(UInt8.random(in: 0...255, using: &generator), at: index)
        }
      }
      do {
        let patch = try Patch(reading: Data(bytes))
        readCount += 1
        for line in patch.files.flatMap(\.hunks).flatMap(\.lines) {
          #expect(line.bytes.upperBound <= patch.bytes.count)
        }
      } catch {
        refusedCount += 1
      }
    }
    #expect(readCount > 0)
    #expect(refusedCount > 0)
  }
}
