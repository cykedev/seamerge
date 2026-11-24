import AppKit
import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

/// Measures keeping the work of a large merge: the snapshot the main actor takes, then capturing,
/// encoding and writing it in the background, and reading and restoring it again, with the size
/// of the file; and on the main actor the first edit after a snapshot, which copies the text and
/// the segments the snapshot still shares, beside an edit that copies nothing.
///
/// The first test copies the two values the window holds; the second takes them out of a window,
/// as the window does it, and measures the hold of the main actor while the window keeps its work;
/// the third measures opening the files with and without work kept for them.
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

  /// Measures keeping the work of a window of the chosen case on the main actor: the snapshot
  /// the window takes of its result, the call that hands it to the background, the longest hold
  /// of the main actor until the work is written, and the first decision after a snapshot,
  /// while the background still shares the text and the segments, beside a decision that
  /// shares nothing.
  @Test(.enabled(if: chosenCase != nil))
  func measureKeepingTheWorkOfAWindowOfTheChosenCase() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let recorder = try LargeFileRecorder(caseName: name)
    let texts = largeCase.texts()
    let session = try await Session.merge(
      base: texts.base.map { SourceFile(bytes: Data($0.utf8), label: "base") },
      a: SourceFile(bytes: Data(texts.a.utf8), label: "a"),
      b: SourceFile(bytes: Data(texts.b.utf8), label: "b"))
    let work = WorkFolder()
    let keeper = work.keeper()
    let controller = try Windows.controller(for: session, workKeeper: keeper)
    let conflicts = controller.presentation.changes.blocks.indices.filter {
      controller.presentation.changes.blocks[$0].kind == .conflict
    }
    try #require(conflicts.count >= 2 * Self.runs + 1)
    let clock = ContinuousClock()
    var timings: [String: [Duration]] = [:]
    func decide(_ number: Int) -> Duration {
      controller.presentation.setCurrentBlock(conflicts[number])
      let start = clock.now
      controller.perform(.useB)
      let duration = clock.now - start
      controller.endEvent()
      return duration
    }
    _ = decide(0)
    for run in 0..<Self.runs {
      var start = clock.now
      let snapshot = controller.workSnapshot
      timings["window-snapshot-main", default: []].append(clock.now - start)
      #expect(snapshot != nil)

      let hold = await LargeFileRun.longestHold {
        start = clock.now
        keeper.keepNow()
        timings["keep-now-main", default: []].append(clock.now - start)
        await keeper.lastOperation?.value
      }
      timings["keep-longest-hold", default: []].append(hold)

      keeper.keepNow()
      timings["decision-after-snapshot-main", default: []].append(decide(2 * run + 1))
      await keeper.lastOperation?.value
      timings["decision-unshared-main", default: []].append(decide(2 * run + 2))
    }
    for (metric, durations) in timings.sorted(by: { $0.key < $1.key }) {
      let sorted = durations.sorted()
      recorder.record(metric, sorted[sorted.count / 2])
      recorder.record("\(metric)-max", sorted[sorted.count - 1])
    }
    recorder.record("blocks", Double(session.blocks.count), unit: "-")
    recorder.finish()
    controller.close()
    await keeper.lastOperation?.value
  }

  /// Measures opening the files of the chosen case as a merge, from the call until the window
  /// is filled: without work kept for them, and with work, which the window reads before it
  /// compares and puts back once it is filled.
  @Test(.enabled(if: chosenCase != nil))
  func measureOpeningTheChosenCaseWithAndWithoutItsWork() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let recorder = try LargeFileRecorder(caseName: name)
    let texts = largeCase.texts()
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "MergeWorkMeasurements-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: folder) } }
    var files: [String: SessionFile] = [:]
    for (role, text) in [("base", texts.base), ("a", texts.a), ("b", texts.b)] {
      guard let text else { continue }
      let url = folder.appending(path: "\(role).\(largeCase.fileExtension)")
      try Data(text.utf8).write(to: url)
      files[role] = SessionFile(url: url, label: url.lastPathComponent)
    }
    let a = try #require(files["a"])
    let b = try #require(files["b"])
    let work = WorkFolder()
    let clock = ContinuousClock()
    func open() async throws -> (SessionWindowController, Duration) {
      let start = clock.now
      let controller = try await SessionWindowController.openMerge(
        base: files["base"], a: a, b: b, mode: .windowDefault, context: SessionContext(),
        undoManager: UndoManager(), settings: .private(), workKeeper: work.keeper())
      await controller.phase.filling?.value
      return (controller, clock.now - start)
    }
    func close(_ controller: SessionWindowController) async {
      controller.close()
      await controller.workKeeper?.lastOperation?.value
    }

    var timings: [String: [Duration]] = [:]
    for _ in 0..<Self.runs {
      let (controller, duration) = try await open()
      timings["open-without-work", default: []].append(duration)
      #expect(controller.restoredWork == nil)
      await close(controller)
    }
    let (worked, _) = try await open()
    worked.perform(.resolveAllWithB)
    worked.endEvent()
    await close(worked)
    #expect(try work.fileNames.count == 1)
    for _ in 0..<Self.runs {
      let (controller, duration) = try await open()
      timings["open-with-work", default: []].append(duration)
      #expect(controller.restoredWork != nil)
      await close(controller)
    }
    for (metric, durations) in timings.sorted(by: { $0.key < $1.key }) {
      let sorted = durations.sorted()
      recorder.record(metric, sorted[sorted.count / 2])
      recorder.record("\(metric)-max", sorted[sorted.count - 1])
    }
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
