import Foundation
import Testing

@testable import Integration

/// The shell behind the dialog of macOS: that every argument reaches the script as one word, how
/// it tells a refusal from a failure, and that it asks for an administrator only when it should.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppleScriptShellTests {
  @Test func appleScriptHandsEveryArgumentToTheShellAsOneWordUnchanged() async throws {
    let folder = try temporaryFolder()
    defer { remove(folder) }
    let output = folder.appending(path: "words")
    let marker = folder.appending(path: "smuggled").path
    let words = [
      "-n", "--", "two words", "'single'", "\"double\"", "$(touch '\(marker)')",
      "`touch '\(marker)'`", "; touch '\(marker)'", "line\nbreak", "trailing\n\n",
      "back\\slash", "*?[a]", "Grüße", "",
    ]
    let script = #"out=$1; shift; for word; do printf '%s\0' "$word"; done > "$out""#

    try await AppleScriptShell(asksForAdministrator: false).run(
      script, arguments: [output.path] + words, prompt: "")

    let written = try Data(contentsOf: output)
    #expect(
      written.split(separator: 0, omittingEmptySubsequences: false).dropLast().map {
        String(decoding: $0, as: UTF8.self)
      } == words)
    #expect(!FileManager.default.fileExists(atPath: marker))
  }

  @Test func appleScriptTellsARefusalOfTheScriptFromAFailure() async {
    let shell = AppleScriptShell(asksForAdministrator: false)

    await #expect(throws: CommandLineToolFailure.otherFile) {
      try await shell.run("exit 3", arguments: [], prompt: "")
    }
    await #expect(throws: CommandLineToolFailure.failed(message: "no space left")) {
      try await shell.run("echo 'no space left' >&2; exit 5", arguments: [], prompt: "")
    }
  }

  @Test func answersOfOsascriptBecomeTheFailuresOfTheSheet() {
    func failure(_ error: String, status: Int32 = 1) -> CommandLineToolFailure? {
      AppleScriptShell.failure(status: status, error: error)
    }

    #expect(failure("", status: 0) == nil)
    #expect(failure("7:30: execution error: User canceled. (-128)\n") == .notAllowed)
    #expect(
      failure(
        "7:30: execution error: The administrator user name or password was "
          + "incorrect. (-60005)") == .notAllowed)
    #expect(
      failure("7:76: execution error: The command exited with a non-zero status. (3)")
        == .otherFile)
    #expect(
      failure("7:76: execution error: ln: /usr/local/bin: Read-only file system (1)")
        == .failed(message: "ln: /usr/local/bin: Read-only file system"))
  }

  @Test func dialogAsksForAnAdministratorWithAPromptOfItsOwn() {
    #expect(
      AppleScriptShell.administrator.sourceLines.contains(
        "do shell script commandLine with administrator privileges with prompt (item 1 of argv)"))
    #expect(
      !AppleScriptShell(asksForAdministrator: false).sourceLines.joined().contains(
        "administrator"))
  }

  /// A new, empty temporary folder.
  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "AppleScriptShell-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func remove(_ folder: URL) {
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The folder of the test could not be removed")
    }
  }
}
