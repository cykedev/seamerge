import Foundation
import Testing

/// Runs the built `mergecli` executable and checks exit status and output.
@Suite("mergecli")
final class CommandLineTests {
  struct Run {
    let status: Int32
    let output: String
    let errors: String
  }

  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mergecliTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  /// Writes `text` to a file in the test's directory and returns its path.
  private func file(_ name: String, _ text: String) throws -> String {
    let url = directory.appendingPathComponent(name)
    try Data(text.utf8).write(to: url)
    return url.path
  }

  private func run(_ arguments: String...) throws -> Run {
    try run(arguments)
  }

  /// Runs `mergecli`, which is built next to the test bundle.
  private func run(_ arguments: [String]) throws -> Run {
    let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = products.appendingPathComponent("mergecli")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Run(
      status: process.terminationStatus,
      output: String(decoding: outputData, as: UTF8.self),
      errors: String(decoding: errorData, as: UTF8.self))
  }

  @Test("Help prints the usage and succeeds")
  func help() throws {
    let result = try run("--help")
    #expect(result.status == 0)
    #expect(result.output.hasPrefix("usage: mergecli diff"))
  }

  @Test(
    "Invalid command lines fail with status 2",
    arguments: [
      (["frobnicate"], "unknown command 'frobnicate'"),
      (["diff", "only-one"], "diff needs two files"),
      (["merge", "a", "b"], "merge needs three files"),
      (["diff", "-q", "a", "b"], "-q is only valid for merge"),
      (["merge", "--tokens", "base", "a", "b"], "--tokens is only valid for diff"),
      (["merge", "--strategy", "fast", "base", "a", "b"], "unknown strategy 'fast'"),
      (["diff", "-", "b"], "reading standard input is not supported"),
      (["diff", "--color", "a", "b"], "unknown option '--color'"),
    ])
  func invalidCommandLines(arguments: [String], message: String) throws {
    let result = try run(arguments)
    #expect(result.status == 2)
    #expect(result.errors.hasPrefix("mergecli: \(message)\n"))
  }

  @Test("diff exits with 0 for identical files and 1 for differences")
  func diffStatus() throws {
    let old = try file("old", "one\ntwo\n")
    let same = try file("same", "one\ntwo\n")
    let new = try file("new", "one\nTWO\n")
    #expect(try run("diff", old, same).status == 0)

    let changed = try run("diff", old, new)
    #expect(changed.status == 1)
    #expect(changed.output.contains("    - two\n    + TWO\n"))
  }

  @Test("A missing file is an error")
  func missingFile() throws {
    let result = try run("diff", "does-not-exist", "neither")
    #expect(result.status == 2)
    #expect(result.errors.hasPrefix("mergecli: cannot read does-not-exist"))
  }

  @Test("A clean merge writes the result and exits with 0")
  func cleanMerge() throws {
    let base = try file("base", "one\ntwo\nthree\n")
    let a = try file("a", "ONE\ntwo\nthree\n")
    let b = try file("b", "one\ntwo\nTHREE\n")
    let result = try run("merge", "-q", base, a, b, "-o", "result")
    #expect(result.status == 0)
    #expect(result.output.isEmpty)
    let merged = try Data(contentsOf: directory.appendingPathComponent("result"))
    #expect(String(decoding: merged, as: UTF8.self) == "ONE\ntwo\nTHREE\n")
  }

  @Test("A conflict exits with 1; with -o - the listing goes to standard error")
  func conflictToStandardOutput() throws {
    let base = try file("base", "value = 1\n")
    let a = try file("a", "value = 2\n")
    let b = try file("b", "value = 3\n")
    let result = try run("merge", "--style", "merge", base, a, b, "-o", "-")
    #expect(result.status == 1)
    #expect(
      result.output == "<<<<<<< \(a)\nvalue = 2\n=======\nvalue = 3\n>>>>>>> \(b)\n")
    #expect(result.errors.contains("1 conflict"))
  }
}
