import Foundation

/// Access to the files in `Fixtures/` (see the README there).
enum Fixtures {
  struct Missing: Error {
    let path: String
  }

  static func data(_ path: String) throws -> Data {
    guard let root = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") else {
      throw Missing(path: path)
    }
    return try Data(contentsOf: root.appendingPathComponent(path))
  }

  static func pair(_ name: String) throws -> (a: Data, b: Data) {
    (try data("\(name)/a"), try data("\(name)/b"))
  }

  static func triple(_ name: String) throws -> (base: Data, a: Data, b: Data) {
    (try data("\(name)/base"), try data("\(name)/a"), try data("\(name)/b"))
  }

  static let mergeCases = [
    "merge-adjacent",
    "merge-clean",
    "merge-conflict",
    "merge-crlf",
    "merge-delete",
    "merge-delete-vs-edit",
    "merge-empty-all",
    "merge-empty-base",
    "merge-empty-both-add",
    "merge-insert-same-place",
    "merge-missing-final-newline",
    "merge-missing-final-newline-conflict",
    "merge-nonutf8",
    "merge-same-change",
    "merge-split-conflict",
    "merge-whitespace-edit",
    "merge-whitespace-vs-edit",
  ]

  /// Two-way cases as (a, b) paths, including both directions of the
  /// empty-file case.
  static let diffCases = [
    ("diff-crlf/a", "diff-crlf/b"),
    ("diff-empty/empty", "diff-empty/empty"),
    ("diff-empty/empty", "diff-empty/content"),
    ("diff-empty/content", "diff-empty/empty"),
    ("diff-missing-final-newline/a", "diff-missing-final-newline/b"),
    ("diff-nonutf8/a", "diff-nonutf8/b"),
    ("diff-two-changes/a", "diff-two-changes/b"),
    ("diff-whitespace/a", "diff-whitespace/b"),
  ]
}

extension Data {
  init(_ text: String) { self.init(text.utf8) }

  var text: String { String(decoding: self, as: UTF8.self) }
}
