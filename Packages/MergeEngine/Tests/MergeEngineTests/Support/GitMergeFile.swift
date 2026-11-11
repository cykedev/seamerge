import Foundation

/// Runs `git merge-file` for comparison with the Perforce engine.
enum GitMergeFile {
  struct Outcome {
    let text: Data
    let conflictCount: Int
  }

  struct Failure: Error {
    let status: Int32
  }

  static let executable: URL? = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
    .map(URL.init(fileURLWithPath:))
    .first { FileManager.default.isExecutableFile(atPath: $0.path) }

  static var isAvailable: Bool { executable != nil }

  /// Runs `git merge-file -p <b> <base> <a>`: B is git's "current" side and
  /// A the "other" side.
  static func merge(base: Data, a: Data, b: Data) throws -> Outcome {
    guard let executable else { throw Failure(status: -1) }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MergeEngineTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let urlB = directory.appendingPathComponent("b")
    let urlBase = directory.appendingPathComponent("base")
    let urlA = directory.appendingPathComponent("a")
    try b.write(to: urlB)
    try base.write(to: urlBase)
    try a.write(to: urlA)

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = ["merge-file", "-p", urlB.path, urlBase.path, urlA.path]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let text = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    // The exit status is the number of conflicts (capped at 127); higher
    // values are errors.
    guard process.terminationReason == .exit, process.terminationStatus < 128 else {
      throw Failure(status: process.terminationStatus)
    }
    return Outcome(text: text, conflictCount: Int(process.terminationStatus))
  }
}
