import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

/// Measures keeping the work of a large merge: the snapshot the main actor takes, then capturing,
/// encoding and writing it in the background, and reading and restoring it again, with the size
/// of the file; and on the main actor the first edit after a snapshot, which copies the text and
/// the segments the snapshot still shares, beside an edit that copies nothing.
///
/// The snapshot here copies the two values the window holds; taking them out of a window, as the
/// window does it, is not measured here.
///
/// The measurements run only on demand, never in the check of the repository: the environment
/// variable `SEAMERGE_MEASURE_WORK` names the case of ``LargeFileCase``, and
/// `SEAMERGE_MEASURE_OUTPUT` the file the values go into, as for ``LargeFileMeasurements``. Run
/// them in a release build.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(10)))
struct MergeWorkMeasurements {
  /// The case the environment chooses, if any.
  nonisolated static var chosenCase: String? {
    ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_WORK"]
  }

  /// How often each step is measured; the median counts.
  static let runs = 7

  @Test(.enabled(if: chosenCase != nil))
  func measureKeepingTheWorkOfTheChosenCase() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let recorder = try LargeFileRecorder(caseName: name)
    let texts = largeCase.texts()
    let session = try await Session.merge(
      base: texts.base.map { SourceFile(bytes: Data($0.utf8), label: "base") },
      a: SourceFile(bytes: Data(texts.a.utf8), label: "a"),
      b: SourceFile(bytes: Data(texts.b.utf8), label: "b"))
    let clock = ContinuousClock()
    let (key, keyDuration) = await Self.key(of: session)
    recorder.record("key", keyDuration)
    let (document, text) = try Self.workedResult(of: session)
    let format = ResultFormat(resultOf: session)
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "MergeWorkMeasurements-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    let store = MergeWorkStore(folder: folder)

    var timings: [String: [Duration]] = [:]
    var size = 0
    for _ in 0..<Self.runs {
      let start = clock.now
      let snapshot = Snapshot(document: document, text: text)
      timings["snapshot-values-main", default: []].append(clock.now - start)

      let background = try await Self.keep(snapshot, key: key, format: format, in: store)
      for (metric, duration) in background.timings {
        timings[metric, default: []].append(duration)
      }
      size = background.size

      let restoreStart = clock.now
      let restoration = try await Self.restore(key, from: store, into: session)
      timings["read-restore", default: []].append(clock.now - restoreStart)
      #expect(restoration.restartedBlockCount == 0)

      for (metric, duration) in try Self.measureEditing(document: document, text: text) {
        timings[metric, default: []].append(duration)
      }
    }
    for (metric, durations) in timings.sorted(by: { $0.key < $1.key }) {
      recorder.record(metric, durations.sorted()[durations.count / 2])
    }
    recorder.record("file-size", Double(size) / 1_000_000, unit: "MB")
    recorder.record("blocks", Double(session.blocks.count), unit: "-")
    recorder.finish()
  }

  /// The time of an edit on the main actor right after a snapshot, while the snapshot still
  /// shares the text and the segments, and of the next edit, when nothing is shared any more.
  static func measureEditing(
    document: ResultDocument, text: String
  ) throws -> [String: Duration] {
    // Copies of their own, so that only the snapshot shares them.
    var resultText = ResultText(String(decoding: Array(text.utf8), as: UTF8.self))
    var editedDocument = document
    try type(in: &editedDocument, &resultText)
    let snapshot = Snapshot(document: editedDocument, text: resultText.string)
    let clock = ContinuousClock()
    var start = clock.now
    try type(in: &editedDocument, &resultText)
    let firstEdit = clock.now - start
    start = clock.now
    try type(in: &editedDocument, &resultText)
    let nextEdit = clock.now - start
    withExtendedLifetime(snapshot) {}
    return ["edit-after-snapshot-main": firstEdit, "edit-unshared-main": nextEdit]
  }

  /// Types a character in the middle of the first segment as the window does: into the text in
  /// the file's form and into the document.
  static func type(in document: inout ResultDocument, _ text: inout ResultText) throws {
    let block = try #require(document.session.blocks.first)
    let range = document.range(of: block)
    let offset = range.lowerBound + range.count / 2
    let plan = document.plan(for: TextReplacement(range: offset..<offset, text: "x"))
    var replacedTexts: [String] = []
    for replacement in plan.replacements {
      replacedTexts.append(text.carryOut(replacement).replacedText)
    }
    document.apply(plan, replacedTexts: replacedTexts)
  }

  /// What the main actor hands to the background: the document and the text, both values.
  struct Snapshot: Sendable {
    let document: ResultDocument
    let text: String
  }

  /// The key of `session`, computed off the main actor, and how long that took.
  @concurrent
  nonisolated static func key(of session: Session) async -> (MergeKey, Duration) {
    let clock = ContinuousClock()
    let start = clock.now
    let key = MergeKey(session.inputs)
    return (key, clock.now - start)
  }

  /// Captures, encodes and writes the work of `snapshot` off the main actor, and returns the time
  /// of each step and the size of the file.
  @concurrent
  nonisolated static func keep(
    _ snapshot: Snapshot, key: MergeKey, format: ResultFormat, in store: MergeWorkStore
  ) async throws -> (timings: [String: Duration], size: Int) {
    let clock = ContinuousClock()
    var start = clock.now
    let work = try #require(
      MergeWork(
        capturing: snapshot.document, text: snapshot.text, key: key, format: format,
        currentBlock: nil, savedAt: Date()))
    let capture = clock.now - start
    start = clock.now
    let size = try JSONEncoder().encode(work).count
    let encode = clock.now - start
    start = clock.now
    try await store.write(work)
    let write = clock.now - start
    return (["capture": capture, "encode": encode, "encode-write": write], size)
  }

  /// Reads the work of `key` and plans restoring it into a fresh result of `session`.
  @concurrent
  nonisolated static func restore(
    _ key: MergeKey, from store: MergeWorkStore, into session: Session
  ) async throws -> WorkRestoration {
    let work = try #require(try await store.read(key))
    return try #require(ResultDocument(session: session).planRestoring(work))
  }

  /// The result of `session` with every other conflict decided and text typed over three block
  /// boundaries, and its text.
  nonisolated static func workedResult(
    of session: Session
  ) throws -> (ResultDocument, String) {
    var document = ResultDocument(session: session)
    let text = NSMutableString(string: document.initialText)
    func carryOut(_ plan: EditPlan) {
      var replacedTexts: [String] = []
      for replacement in plan.replacements {
        let range = NSRange(
          location: replacement.range.lowerBound, length: replacement.range.count)
        replacedTexts.append(text.substring(with: range))
        text.replaceCharacters(in: range, with: replacement.text)
      }
      document.apply(plan, replacedTexts: replacedTexts)
    }
    let conflicts = session.blocks.filter { $0.kind == .conflict }
    for conflict in conflicts.enumerated().filter({ $0.offset.isMultiple(of: 2) }).map(\.element) {
      carryOut(document.planChoosing([.a, .b], in: conflict))
    }
    var boundaries = 0
    for index in session.blocks.indices.dropLast() where boundaries < 3 {
      let first = document.range(of: session.blocks[index])
      let second = document.range(of: session.blocks[index + 1])
      guard first.count > 10, second.count > 10,
        document.segment(for: session.blocks[index]).state != .open,
        document.segment(for: session.blocks[index + 1]).state != .open
      else { continue }
      carryOut(
        document.plan(
          for: TextReplacement(
            range: first.upperBound - 5..<second.lowerBound + 5, text: "typed by hand")))
      boundaries += 1
    }
    try #require(boundaries == 3)
    return (document, text as String)
  }
}
