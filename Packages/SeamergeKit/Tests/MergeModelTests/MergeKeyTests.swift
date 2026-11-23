import Foundation
import MergeModel
import Testing

struct MergeKeyTests {
  /// The inputs of a merge with `base`, `a` and `b` as their UTF-8 content.
  static func inputs(base: String?, a: String, b: String) -> Session.Inputs<SourceFile> {
    Session.Inputs(
      base: base.map { SourceFile($0, label: "base") }, a: SourceFile(a, label: "a"),
      b: SourceFile(b, label: "b"))
  }

  @Test func sameContentUnderOtherPathsGivesTheSameKey() throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "MergeKeyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    var keys: [MergeKey] = []
    for run in ["first", "second"] {
      let runFolder = folder.appending(path: run, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true)
      var files: [Role: SourceFile] = [:]
      for (role, text) in [(Role.base, "o\n"), (.a, "a\n"), (.b, "b\n")] {
        let url = runFolder.appending(path: "story_\(role)_\(run).txt")
        try Data(text.utf8).write(to: url)
        files[role] = try SourceFile(contentsOf: url, label: "\(role)")
      }
      keys.append(
        MergeKey(
          Session.Inputs(
            base: files[.base], a: try #require(files[.a]), b: try #require(files[.b]))))
    }

    #expect(keys[0] == keys[1])
  }

  @Test(arguments: Role.allCases)
  func changedByteInAnyInputGivesAnotherKey(role: Role) {
    let original = MergeKey(Self.inputs(base: "base\n", a: "side a\n", b: "side b\n"))

    let changed = MergeKey(
      Self.inputs(
        base: role == .base ? "basE\n" : "base\n", a: role == .a ? "side A\n" : "side a\n",
        b: role == .b ? "side B\n" : "side b\n"))

    #expect(changed != original)
  }

  @Test func mergeWithoutBaseDiffersFromMergeWithEmptyBase() {
    let withoutBase = MergeKey(Self.inputs(base: nil, a: "a\n", b: "b\n"))
    let emptyBase = MergeKey(Self.inputs(base: "", a: "a\n", b: "b\n"))

    #expect(withoutBase != emptyBase)
  }

  @Test func lengthsKeepTheContentsOfTheInputsApart() {
    let first = MergeKey(Self.inputs(base: "", a: "ab", b: "c"))
    let second = MergeKey(Self.inputs(base: "", a: "a", b: "bc"))

    #expect(first != second)
  }

  /// The digests were computed outside the app with `shasum -a 256`, so that a change of the key
  /// across versions shows here.
  @Test func keyIsTheDigestOfTheLengthPrefixedContents() {
    #expect(
      MergeKey(Self.inputs(base: "o\n", a: "a\n", b: "b\n")).rawValue
        == "013664bb64732c981b74d0c86b8dd0b3884f00f67c8c32a086337f0072336758")
    #expect(
      MergeKey(Self.inputs(base: nil, a: "a\n", b: "b\n")).rawValue
        == "70350af55cc21e490a0a53a8288ac4f0f69ba478b015a0efab01446bdff6af4b")
  }

  @Test func rawValueRoundTripsAndOnlyLowercaseDigestsAreKeys() {
    let key = MergeKey(Self.inputs(base: "o\n", a: "a\n", b: "b\n"))

    #expect(MergeKey(rawValue: key.rawValue) == key)
    #expect(MergeKey(rawValue: key.rawValue.uppercased()) == nil)
    #expect(MergeKey(rawValue: String(key.rawValue.dropLast())) == nil)
    #expect(MergeKey(rawValue: "notes") == nil)
  }
}
