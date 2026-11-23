import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

@Suite(.timeLimit(.minutes(1)))
struct MergeWorkStoreTests {
  /// The time the tests take as now.
  static let now = Date(timeIntervalSinceReferenceDate: 812_345_678)

  static let day: TimeInterval = 24 * 60 * 60

  /// Runs `body` with a folder of its own that does not exist yet, which is removed afterwards.
  static func withFolder(_ body: (URL) async throws -> Void) async throws {
    let parent = FileManager.default.temporaryDirectory
      .appending(path: "MergeWorkStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: parent) } }
    try await body(parent.appending(path: "Merges", directoryHint: .isDirectory))
  }

  /// The work of a merge whose A differs by `number`, with its conflict decided, captured at
  /// `savedAt`.
  static func work(_ number: Int, savedAt: Date = now) async throws -> MergeWork {
    let base = SourceFile(bytes: Data("line\n".utf8), label: "base")
    let a = SourceFile(bytes: Data("line \(number) from a\n".utf8), label: "a")
    let b = SourceFile(bytes: Data("line from b\n".utf8), label: "b")
    let session = try await Session.merge(base: base, a: a, b: b)
    var document = ResultDocument(session: session)
    let conflict = try #require(session.blocks.first { $0.kind == .conflict })
    let plan = document.planChoosing([.a], in: conflict)
    var text = document.initialText as NSString
    var replacedTexts: [String] = []
    for replacement in plan.replacements {
      let range = NSRange(
        location: replacement.range.lowerBound, length: replacement.range.count)
      replacedTexts.append(text.substring(with: range))
      text = text.replacingCharacters(in: range, with: replacement.text) as NSString
    }
    document.apply(plan, replacedTexts: replacedTexts)
    return try #require(
      MergeWork(
        capturing: document, text: text as String, key: MergeKey(session.inputs),
        format: ResultFormat(resultOf: session), currentBlock: conflict, savedAt: savedAt))
  }

  /// The names of the files in `folder`, sorted.
  static func fileNames(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
      .sorted()
  }

  /// Writes `text` to the file `name` in `folder`.
  static func writeFile(_ text: String, named name: String, in folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: folder.appending(path: name))
  }

  @Test func workOfTheUserIsKeptInApplicationSupport() {
    let path = MergeWorkStore.standardFolder.path(percentEncoded: false)

    #expect(path.hasSuffix("/Library/Application Support/Seamerge/Merges/"))
  }

  @Test func writtenWorkReadsBackUntilItIsRemoved() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })
      let work = try await Self.work(1)

      try await store.write(work)

      #expect(try Self.fileNames(in: folder) == ["\(work.key.rawValue).json"])
      #expect(try await store.read(work.key) == work)
      try await store.remove(work.key)
      #expect(try await store.read(work.key) == nil)
      try await store.remove(work.key)
    }
  }

  @Test func writingReplacesTheEarlierWorkOfTheMerge() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })
      let earlier = try await Self.work(1, savedAt: Self.now - Self.day)
      let later = try await Self.work(1)

      try await store.write(earlier)
      try await store.write(later)

      #expect(try Self.fileNames(in: folder).count == 1)
      #expect(try await store.read(later.key) == later)
    }
  }

  @Test func readingWithoutAFolderFindsNoWork() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })

      let key = try await Self.work(1).key
      #expect(try await store.read(key) == nil)
      await store.removeExpired()
    }
  }

  @Test func unreadableWorkAndWorkOfAnotherVersionAreReportedAndStay() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })
      let damaged = try await Self.work(1)
      let newer = try await Self.work(2)
      let misplaced = try await Self.work(3)
      try Self.writeFile(
        "{\"formatVersion\": 1, \"key\":", named: "\(damaged.key.rawValue).json", in: folder)
      try Self.writeFile(
        "{\"formatVersion\": 2}", named: "\(newer.key.rawValue).json", in: folder)
      let other = try await Self.work(4)
      try await store.write(other)
      try FileManager.default.moveItem(
        at: folder.appending(path: "\(other.key.rawValue).json"),
        to: folder.appending(path: "\(misplaced.key.rawValue).json"))

      await #expect {
        try await store.read(damaged.key)
      } throws: {
        if case .unreadable = $0 as? MergeWorkStoreError { true } else { false }
      }
      await #expect(throws: MergeWorkStoreError.unknownFormatVersion(2)) {
        try await store.read(newer.key)
      }
      await #expect {
        try await store.read(misplaced.key)
      } throws: {
        if case .unreadable = $0 as? MergeWorkStoreError { true } else { false }
      }
      #expect(try Self.fileNames(in: folder).count == 3)
    }
  }

  @Test func workOlderThanThirtyDaysIsRemovedAndOtherFilesStay() async throws {
    try await Self.withFolder { folder in
      let ages = [31, 29, 1]
      var works: [MergeWork] = []
      for (number, age) in ages.enumerated() {
        works.append(try await Self.work(number, savedAt: Self.now - Double(age) * Self.day))
      }
      // Written while none of them had expired yet.
      let earlierStore = MergeWorkStore(folder: folder, now: { Self.now - 2 * Self.day })
      for work in works {
        try await earlierStore.write(work)
      }
      let unreadable = try await Self.work(10).key.rawValue + ".json"
      let newer = try await Self.work(11).key.rawValue + ".json"
      try Self.writeFile("not json", named: unreadable, in: folder)
      try Self.writeFile("{\"formatVersion\": 2}", named: newer, in: folder)
      try Self.writeFile("notes", named: "notes.txt", in: folder)
      try Self.writeFile("{}", named: "draft.json", in: folder)
      let store = MergeWorkStore(folder: folder, now: { Self.now })

      await store.removeExpired()

      #expect(try await store.read(works[0].key) == nil)
      #expect(try await store.read(works[1].key) == works[1])
      #expect(try await store.read(works[2].key) == works[2])
      #expect(
        try Self.fileNames(in: folder)
          == [
            "\(works[1].key.rawValue).json", "\(works[2].key.rawValue).json", unreadable, newer,
            "notes.txt", "draft.json",
          ].sorted())
    }
  }

  @Test func onlyTheNewestHundredOfThisVersionAreKeptAndOtherFilesDoNotCount() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })
      var others: [String] = []
      for number in 1_000..<1_003 {
        // Work of a later version, newer than any work of this one, as after a downgrade.
        let name = try await Self.work(number).key.rawValue + ".json"
        try Self.writeFile(
          "{\"blocks\":\"\",\"formatVersion\":2,\"savedAt\":\(Self.now.timeIntervalSinceReferenceDate),"
            + "\"segments\":[]}", named: name, in: folder)
        others.append(name)
      }
      let unreadable = try await Self.work(1_003).key.rawValue + ".json"
      try Self.writeFile("not json", named: unreadable, in: folder)
      others.append(unreadable)
      var works: [MergeWork] = []
      for number in 0..<(MergeWorkStore.capacity + 3) {
        let work = try await Self.work(number, savedAt: Self.now - Double(200 - number) * 60)
        works.append(work)
        try await store.write(work)
      }

      let names = Set(try Self.fileNames(in: folder))

      #expect(names.count == MergeWorkStore.capacity + others.count)
      #expect(names.isSuperset(of: others))
      for (index, work) in works.enumerated() {
        #expect(names.contains("\(work.key.rawValue).json") == (index >= 3), "work \(index)")
      }
    }
  }

  @Test func ageCountsFromTheCaptureNotFromTheFile() async throws {
    try await Self.withFolder { folder in
      let store = MergeWorkStore(folder: folder, now: { Self.now })
      let recent = try await Self.work(1, savedAt: Self.now - Self.day)
      let expired = try await Self.work(2, savedAt: Self.now - 31 * Self.day)
      try await store.write(recent)
      try FileManager.default.setAttributes(
        [.modificationDate: Self.now - 60 * Self.day],
        ofItemAtPath: folder.appending(path: "\(recent.key.rawValue).json")
          .path(percentEncoded: false))

      try await store.write(expired)

      #expect(try Self.fileNames(in: folder) == ["\(recent.key.rawValue).json"])
    }
  }

  @Test func headOfLargeWorkFitsTheBytesTheStoreReadsToDateIt() async throws {
    try await Self.withFolder { folder in
      let work = try await Self.largeWork(savedAt: Self.now - 31 * Self.day)
      // Written while it had not expired yet.
      try await MergeWorkStore(folder: folder, now: { Self.now - 2 * Self.day }).write(work)
      let data = try Data(contentsOf: folder.appending(path: "\(work.key.rawValue).json"))
      let segments = try #require(data.firstRange(of: Data(#","segments":"#.utf8)))
      try #require(data.count > 1_000_000)

      #expect(segments.lowerBound < MergeWorkStore.headLength)
      await MergeWorkStore(folder: folder, now: { Self.now }).removeExpired()
      #expect(try Self.fileNames(in: folder).isEmpty)
    }
  }

  /// Work with thousands of segments, every conflict decided, more than a megabyte of text and
  /// the last block current, so that every field before the segments is as large as it gets.
  static func largeWork(savedAt: Date) async throws -> MergeWork {
    let lines = (0..<20_000).map { "line \($0) of a long file that the merge keeps\n" }
    func text(changingEvery step: Int, with mark: String) -> Data {
      Data(
        lines.enumerated().map { $0.offset % step == 0 ? mark + $0.element : $0.element }
          .joined().utf8)
    }
    let session = try await Session.merge(
      base: SourceFile(bytes: text(changingEvery: Int.max, with: ""), label: "base"),
      a: SourceFile(bytes: text(changingEvery: 4, with: "a "), label: "a"),
      b: SourceFile(bytes: text(changingEvery: 4, with: "b "), label: "b"))
    var document = ResultDocument(session: session)
    let plan = document.planResolvingOpenConflicts(with: [.a, .b])
    let text = NSMutableString(string: document.initialText)
    var replacedTexts: [String] = []
    for replacement in plan.replacements {
      let range = NSRange(location: replacement.range.lowerBound, length: replacement.range.count)
      replacedTexts.append(text.substring(with: range))
      text.replaceCharacters(in: range, with: replacement.text)
    }
    document.apply(plan, replacedTexts: replacedTexts)
    try #require(session.blocks.count > 5_000)
    return try #require(
      MergeWork(
        capturing: document, text: text as String, key: MergeKey(session.inputs),
        format: ResultFormat(resultOf: session), currentBlock: session.blocks.last,
        savedAt: savedAt))
  }

  @Test func folderThatCannotBeWrittenReportsAnError() async throws {
    try await Self.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let path = folder.path(percentEncoded: false)
      try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
      defer {
        #expect(throws: Never.self) {
          try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        }
      }
      let store = MergeWorkStore(folder: folder, now: { Self.now })

      let work = try await Self.work(1)
      await #expect {
        try await store.write(work)
      } throws: {
        if case .writingFailed = $0 as? MergeWorkStoreError { true } else { false }
      }
      #expect(try Self.fileNames(in: folder).isEmpty)
    }
  }
}
