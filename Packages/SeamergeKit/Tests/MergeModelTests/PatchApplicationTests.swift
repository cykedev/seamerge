import Foundation
import MergeModel
import Testing

/// Patches tried in throwaway repositories: `git apply` and `patch -p1` take them and make the
/// newer files byte for byte, and `git diff` writes the same text.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PatchApplicationTests {
  /// Files before and after a change, by path; a file missing on one side is new or deleted.
  struct Change: CustomTestStringConvertible, Sendable {
    let name: String
    let old: [String: Data]
    let new: [String: Data]

    var testDescription: String { name }

    /// The files of the patch from `old` to `new`, by path.
    var files: [UnifiedDiff.File] {
      Set(old.keys).union(new.keys).sorted().map { path in
        UnifiedDiff.File(old: Self.side(old[path]), new: Self.side(new[path]), names: .path(path))
      }
    }

    private static func side(_ bytes: Data?) -> UnifiedDiff.File.Side {
      bytes.map { .file(SourceFile(bytes: $0, label: "side")) } ?? .missing
    }
  }

  static let changes: [Change] = [
    Change(
      name: "changed file", old: ["notes.txt": text(lines: 1...30)],
      new: ["notes.txt": text(lines: 1...30, replacing: [3: "three", 20: "twenty", 21: "21b"])]),
    Change(name: "new file", old: [:], new: ["new.txt": Data("first\nsecond\n".utf8)]),
    Change(name: "deleted file", old: ["old.txt": Data("first\nsecond\n".utf8)], new: [:]),
    Change(
      name: "CRLF", old: ["windows.txt": Data("one\r\ntwo\r\nthree\r\n".utf8)],
      new: ["windows.txt": Data("one\r\n2\r\nthree\r\nfour\r\n".utf8)]),
    Change(
      name: "line endings changed", old: ["mixed.txt": Data("one\r\ntwo\r\nthree\r\n".utf8)],
      new: ["mixed.txt": Data("one\ntwo\r\nthree\n".utf8)]),
    Change(
      name: "no line break at the end", old: ["a.txt": Data("one\ntwo".utf8)],
      new: ["a.txt": Data("one\nzwei".utf8)]),
    Change(
      name: "line break added at the end", old: ["a.txt": Data("one\ntwo".utf8)],
      new: ["a.txt": Data("one\ntwo\n".utf8)]),
    Change(
      name: "line break removed at the end", old: ["a.txt": Data("one\ntwo\n".utf8)],
      new: ["a.txt": Data("one\ntwo".utf8)]),
    Change(
      name: "space in the path", old: ["My Notes/to do.txt": Data("milk\neggs\n".utf8)],
      new: ["My Notes/to do.txt": Data("milk\nbread\neggs\n".utf8)]),
    Change(
      name: "collection of three files",
      old: [
        "Sources/App.swift": text(lines: 1...12),
        "Sources/Old.swift": Data("gone\n".utf8),
      ],
      new: [
        "Sources/App.swift": text(lines: 1...12, replacing: [6: "six"]),
        "Tests/AppTests.swift": Data("test\n".utf8),
      ]),
    Change(
      name: "ISO 8859-1", old: ["latin1.txt": Data([0x47, 0x72, 0xF6, 0xDF, 0x65, 0x0A])],
      new: ["latin1.txt": Data([0x47, 0x72, 0xD6, 0xDF, 0x45, 0x0A])]),
    Change(
      name: "UTF-8 with byte order mark",
      old: ["bom.txt": Data([0xEF, 0xBB, 0xBF]) + Data("first\nsecond\n".utf8)],
      new: ["bom.txt": Data([0xEF, 0xBB, 0xBF]) + Data("first\n2nd\n".utf8)]),
    Change(
      name: "line endings of CR alone", old: ["mac.txt": Data("one\rtwo\r".utf8)],
      new: ["mac.txt": Data("one\r2\r".utf8)]),
  ]

  @Test(arguments: changes)
  func gitApplyAndPatchTakeThePatchAndMakeTheNewFiles(change: Change) throws {
    let patch = try UnifiedDiff.data(of: change.files)
    let trial = try PatchTrial(files: change.old)
    defer { trial.remove() }

    let checked = try trial.gitApply(["--check"], patch)
    #expect(checked.status == 0, "git apply --check: \(checked.output)")
    let dryRun = try trial.patch(["-p1", "--dry-run"], with: patch)
    #expect(dryRun.status == 0, "patch -p1 --dry-run: \(dryRun.output)")
    #expect(try trial.files() == change.old, "A check leaves the files as they are")

    let applied = try trial.gitApply([], patch)
    #expect(applied.status == 0, "git apply: \(applied.output)")
    #expect(try trial.files() == change.new, "git apply")

    try trial.replaceFiles(with: change.old)
    let patched = try trial.patch(["-p1", "-E"], with: patch)
    #expect(patched.status == 0, "patch -p1: \(patched.output)")
    #expect(try trial.files() == change.new, "patch -p1")
  }

  @Test(arguments: changes)
  func patchHasTheTextOfGitDiffWithoutItsIndexLinesAndFunctionNames(change: Change) throws {
    let trial = try PatchTrial(files: change.old)
    defer { trial.remove() }
    try commitAll(in: trial)
    try trial.replaceFiles(with: change.new)
    try #require(try trial.git(["add", "--all"]).status == 0)

    let gitDiff = try trial.git(["diff", "--cached", "--no-renames"])

    try #require(gitDiff.status == 0, "git diff: \(gitDiff.output)")
    #expect(
      try Self.withoutIndexLinesAndFunctionNames(gitDiff.output)
        == String(decoding: UnifiedDiff.data(of: change.files), as: UTF8.self))
  }

  /// Paths that Git quotes are written and read back as Git does.
  ///
  /// Git quotes a path that holds a quote, a control character or a byte outside ASCII, and
  /// `git apply` reads the quotes back. The `patch` that comes with macOS does not read them and
  /// finds no file to patch, so it is not tried here; paths without quotes, a space among them,
  /// are tried with both tools above.
  @Test func pathsThatGitQuotesHaveTheTextOfGitDiffAndApplyWithGit() throws {
    let change = Change(
      name: "quoted paths",
      old: ["Größe.txt": Data("klein\n".utf8), "say \"hi\".txt": Data("hi\n".utf8)],
      new: ["Größe.txt": Data("groß\n".utf8), "say \"hi\".txt": Data("hello\n".utf8)])
    let patch = try UnifiedDiff.data(of: change.files)
    let trial = try PatchTrial(files: change.old)
    defer { trial.remove() }
    try commitAll(in: trial)

    let applied = try trial.gitApply([], patch)
    try #require(applied.status == 0, "git apply: \(applied.output)")
    #expect(try trial.files() == change.new)
    try #require(try trial.git(["add", "--all"]).status == 0)
    let gitDiff = try trial.git(["diff", "--cached", "--no-renames"])
    #expect(
      try Self.withoutIndexLinesAndFunctionNames(gitDiff.output)
        == String(decoding: patch, as: UTF8.self))
  }

  @Test func randomChangesApplyByteForByte() throws {
    let seed: UInt64 = 32
    var generator = SplitMix64(seed: seed)
    let trial = try PatchTrial(files: [:])
    defer { trial.remove() }
    for run in 0..<80 {
      let old = Self.randomText(using: &generator)
      let new = Self.randomEdit(of: old, using: &generator)
      guard new != old else { continue }
      let change = Change(name: "random", old: ["f.txt": old], new: ["f.txt": new])
      let patch = try UnifiedDiff.data(of: change.files)
      try trial.replaceFiles(with: change.old)

      let applied = try trial.gitApply([], patch)

      let context = Comment(rawValue: "seed \(seed), run \(run)")
      try #require(applied.status == 0, "\(context): \(applied.output)")
      #expect(try trial.files() == change.new, context)
    }
  }

  private func commitAll(in trial: PatchTrial) throws {
    try #require(try trial.git(["add", "--all"]).status == 0)
    let committed = try trial.git([
      "-c", "user.name=Seamerge Tests", "-c", "user.email=tests@example.invalid", "commit",
      "--quiet", "--allow-empty", "--message", "Before",
    ])
    try #require(committed.status == 0, "git commit: \(committed.output)")
  }

  /// The output of `git diff` without the lines `index`, which name objects that a patch of files
  /// does not know, and without the function name after each hunk header, which is optional.
  private static func withoutIndexLinesAndFunctionNames(_ diff: String) throws -> String {
    let functionName = try Regex(#"^(@@ [^@]* @@).*$"#).anchorsMatchLineEndings()
    return diff.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.hasPrefix("index ") }
      .map { $0.replacing(functionName) { $0.output[1].substring ?? "" } }
      .joined(separator: "\n")
  }

  /// Lines `l<number>` for `numbers`, with the lines in `replacing` in place of theirs.
  private static func text(lines numbers: ClosedRange<Int>, replacing: [Int: String] = [:]) -> Data
  {
    Data(numbers.map { "\(replacing[$0] ?? "l\($0)")\n" }.joined().utf8)
  }

  /// A text of lines drawn from a few, so that lines recur, ending in LF or CRLF, and the last
  /// one now and then without a line break.
  private static func randomText(using generator: inout SplitMix64) -> Data {
    let words = ["alpha", "beta", "gamma", "", "  indented", "delta\t", "}"]
    var text = ""
    for _ in 0..<Int.random(in: 0...25, using: &generator) {
      text += words.randomElement(using: &generator) ?? ""
      text += Bool.random(using: &generator) ? "\n" : "\r\n"
    }
    if !text.isEmpty, Int.random(in: 0..<4, using: &generator) == 0 {
      text.removeLast()
    }
    return Data(text.utf8)
  }

  /// `text` with lines removed, inserted, changed or given another line ending.
  private static func randomEdit(of text: Data, using generator: inout SplitMix64) -> Data {
    var lines = String(decoding: text, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: false
    ).map(String.init)
    for _ in 0..<Int.random(in: 1...4, using: &generator) {
      let index = Int.random(in: 0...lines.count, using: &generator)
      switch Int.random(in: 0..<4, using: &generator) {
      case 0 where index < lines.count: lines.remove(at: index)
      case 1: lines.insert("new \(index)\r", at: index)
      case 2 where index < lines.count: lines[index] += " changed"
      case 3 where index < lines.count:
        lines[index] =
          lines[index].hasSuffix("\r") ? String(lines[index].dropLast()) : lines[index] + "\r"
      default: break
      }
    }
    return Data(lines.joined(separator: "\n").utf8)
  }
}
