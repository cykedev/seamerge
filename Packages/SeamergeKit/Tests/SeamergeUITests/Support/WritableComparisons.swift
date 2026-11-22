import Foundation
import MergeModel

@testable import SeamergeUI

/// Comparisons of files on disk, which copying changes may write to.
enum WritableComparisons {
  /// The comparison of `old` with `new`, each written into a file of a new temporary folder
  /// and read from there, as the app reads the files it compares.
  static func diff(
    old: Data, new: Data, oldName: String = "Greeting-old.swift",
    newName: String = "Greeting.swift", mode: ComparisonMode = .windowDefault
  ) async throws -> Session {
    let folder = try filesFolder.get().appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let oldURL = folder.appending(path: oldName)
    let newURL = folder.appending(path: newName)
    try old.write(to: oldURL)
    try new.write(to: newURL)
    return try await Session.diff(
      old: SourceFile(contentsOf: oldURL, label: oldName),
      new: SourceFile(contentsOf: newURL, label: newName), mode: mode)
  }

  /// The folder that holds the files of this run of the tests, emptied of those of an earlier
  /// run the first time it is asked for.
  private static let filesFolder = Result {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "SeamergeUITests-WritableComparisons", directoryHint: .isDirectory)
    if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: folder)
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// The comparison of `old` with `new` as UTF-8 files.
  static func diff(
    old: String, new: String, mode: ComparisonMode = .windowDefault
  ) async throws -> Session {
    try await diff(old: Data(old.utf8), new: Data(new.utf8), mode: mode)
  }

  /// The files of ``SampleDiffs/greeting()`` on disk: an insertion, a change and a removal.
  static func greeting() async throws -> Session {
    try await diff(old: SampleDiffs.greetingOld, new: SampleDiffs.greetingNew)
  }

  /// The files of ``SampleDiffs/everyKindOfChange(repeats:longLines:)`` on disk.
  static func everyKindOfChange() async throws -> Session {
    try await onDisk(try await SampleDiffs.everyKindOfChange(), named: "Kinds")
  }

  /// The files of ``SampleDiffs/manyChanges(lineCount:spacing:)`` on disk, a change every
  /// `spacing` lines, whose long runs of unchanged lines collapse.
  static func manyChanges(spacing: Int = 20) async throws -> Session {
    try await onDisk(try await SampleDiffs.manyChanges(spacing: spacing), named: "Values")
  }

  /// Files whose newer one adds lines at its start, after each of the next two lines and at its
  /// end, and lacks two lines of the older one: bins at the start of the rows and one line apart.
  static func denseInsertions() async throws -> Session {
    let old = ["line 1", "line 2", "line 3", "removed 1", "removed 2", "line 4", "line 5"]
    let new = [
      "inserted at the start", "line 1", "inserted 1", "line 2", "inserted 2", "line 3",
      "line 4", "line 5", "inserted at the end",
    ]
    func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
    return try await diff(old: text(old), new: text(new))
  }

  /// The files of `session` on disk, named after `name`.
  private static func onDisk(_ session: Session, named name: String) async throws -> Session {
    try await diff(
      old: session.inputs.a.bytes, new: session.inputs.b.bytes, oldName: "\(name)-old.swift",
      newName: "\(name).swift")
  }
}
