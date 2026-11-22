import Foundation
import Testing

/// Measures how a large comparison or merge behaves, phase by phase, until the window is laid
/// out and drawn again: opening, coloring, copying a change and undoing the copy, scrolling,
/// jumping, showing all lines, switching the arrangement and the comparison mode, undoing and
/// redoing that switch, searching, also right after the switch, deciding and typing, and the
/// memory after each phase.
///
/// The measurements run only on demand, never in the check of the repository: the environment
/// variable `SEAMERGE_MEASURE_CASE` names the case of ``LargeFileCase``, and
/// `SEAMERGE_MEASURE_OUTPUT` the file the values go into. `Scripts/measure-large-files.sh`
/// runs them in a release build, each case in a process of its own, and sums them up.
///
/// A case of 500,000 lines can take longer than 20 minutes, so the time limit is an hour; the
/// script stops a case earlier when told to.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(60)))
struct LargeFileMeasurements {
  /// The case the environment chooses, if any.
  nonisolated static var chosenCase: String? {
    ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_CASE"]
  }

  /// Whether the environment asks to measure only how the chosen case opens as the app opens
  /// it, in a process of its own.
  nonisolated static var measuresOpening: Bool {
    ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_OPENING"] == "1"
  }

  /// The folder to write the files of the chosen case into, if the environment names one.
  nonisolated static var folderForFiles: String? {
    ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_FILES"]
  }

  @Test(.enabled(if: chosenCase != nil && folderForFiles == nil && !measuresOpening))
  func measureTheChosenCase() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let recorder = try LargeFileRecorder(caseName: name)
    recorder.begin("open")
    let run = try await LargeFileRun(largeCase, recorder: recorder)
    let opened = run.clock.now
    try await run.phase("syntax") { try await run.measureColoring(since: opened) }
    try await run.phase("wordmarks") { try run.measureWordMarks() }
    try await run.phase("copy") { try await run.measureCopying() }
    try await run.phase("scroll") {
      try run.scroll("40pt", step: { _ in 40 }, count: 60)
      try run.scroll("page", step: { $0 }, count: 30)
    }
    await run.phase("jumps") { run.measureJumps() }
    if largeCase.isMerge {
      try await run.phase("deciding-collapsed") { try run.measureDecidingAndTyping("collapsed") }
    }
    await run.phase("show-all-lines") { run.measureShowingAllLines() }
    try await run.phase("scroll-expanded") {
      try run.scroll("expanded-40pt", step: { _ in 40 }, count: 60)
    }
    if largeCase.isMerge {
      try await run.phase("deciding-expanded") { try run.measureDecidingAndTyping("expanded") }
    }
    await run.phase("arrangements") { run.measureArrangements() }
    await run.phase("mode-switch") { await run.measureSwitchingTheMode() }
    // Searching right after the switch, while the window has just put in the new comparison.
    try await run.phase("search-after-switch") {
      try await run.measureSearching(as: "search-after-switch")
    }
    run.pause(.seconds(1))
    await run.phase("mode-switch-undo") { await run.measureUndoingTheSwitch() }
    // The user reads the new comparison before searching it; a search right after the switch
    // measures a race of the finder with the new content instead.
    run.pause(.seconds(1))
    try await run.phase("search") { try await run.measureSearching() }
    recorder.finish()
  }

  /// Measures how the chosen case opens as the app opens it: the window with its headers, then
  /// with its lines.
  @Test(.enabled(if: chosenCase != nil && folderForFiles == nil && measuresOpening))
  func measureOpeningTheChosenCase() async throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let recorder = try LargeFileRecorder(caseName: name)
    recorder.begin("opening")
    try await LargeFileRun.measureOpening(of: largeCase, recorder: recorder)
    recorder.finish()
  }

  /// Writes the files of the chosen case into the folder the environment names, to open them in
  /// the app by hand or for a measurement on the screen.
  @Test(.enabled(if: chosenCase != nil && folderForFiles != nil))
  func writeTheFilesOfTheChosenCase() throws {
    let name = try #require(Self.chosenCase)
    let largeCase = try #require(LargeFileCase.all.first { $0.name == name }, "No case \(name)")
    let folder = URL(filePath: try #require(Self.folderForFiles), directoryHint: .isDirectory)
    _ = try LargeFileRun.writeFiles(of: largeCase, into: folder)
  }
}
