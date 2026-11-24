import Foundation
import SeamergeCLI
import SessionIPC
import Testing

@Suite("Patch", .timeLimit(.minutes(1)))
struct PatchCommandTests {
  private static let patch = """
    diff --git a/notes.txt b/notes.txt
    --- a/notes.txt
    +++ b/notes.txt
    @@ -1,2 +1,2 @@
     first
    -second
    +2nd

    """

  @Test func patchFromAFileGoesToTheAppWithItsBytesAndName() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .open)

      let result = await sandbox.run(["patch", "change.patch"])

      #expect(result == CommandResult(exitStatus: 0))
      let patch = try #require(try await app.nextRequest().patch)
      #expect(patch == SessionRequest.Patch(text: Data(Self.patch.utf8), fileName: "change.patch"))
      await app.stop()
    }
  }

  @Test(arguments: [[], ["patch"], ["patch", "-"]])
  func patchOnStandardInputGoesToTheAppWithoutName(arguments: [String]) async throws {
    try await withSandbox { sandbox in
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .open)

      let result = await sandbox.run(arguments, standardInput: try Self.pipe(Self.patch))

      #expect(result == CommandResult(exitStatus: 0))
      let patch = try #require(try await app.nextRequest().patch)
      #expect(patch == SessionRequest.Patch(text: Data(Self.patch.utf8)))
      await app.stop()
    }
  }

  @Test func fileAsStandardInputCountsAsAPatch() async throws {
    try await withSandbox { sandbox in
      let file = try sandbox.makeFile("change.patch", text: Self.patch)
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .open)

      let result = await sandbox.run(
        [], standardInput: StandardInput(try FileHandle(forReadingFrom: file)))

      #expect(result.exitStatus == 0)
      #expect(try await app.nextRequest().patch?.text == Data(Self.patch.utf8))
      await app.stop()
    }
  }

  @Test func withoutWaitTheCommandEndsWhileTheWindowStaysOpen() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .open)

      #expect(await sandbox.run(["patch", "change.patch"]) == CommandResult(exitStatus: 0))
      await app.stop()
    }
  }

  @Test func withWaitTheCommandEndsOnceTheWindowCloses() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      var app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))

      let result = await sandbox.run(["patch", "--wait", "change.patch"])

      #expect(result == CommandResult(exitStatus: 0))
      #expect(try await app.nextRequest().patch?.waitsForWindow == true)
      await app.stop()
    }
  }

  @Test func withWaitALostConnectionEndsWithOne() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .disconnect)

      let result = await sandbox.run(["patch", "--wait", "change.patch"])

      #expect(result.exitStatus == 1)
      #expect(result.errorOutput.hasPrefix("seamerge: Lost the connection to Seamerge"))
      await app.stop()
    }
  }

  @Test(arguments: ["", "\n"])
  func patchWithoutChangesOpensNothingAndSaysSo(text: String) async throws {
    try await withSandbox { sandbox in
      let command = sandbox.command(launcher: AppThatCannotStart(), connectionTimeout: .zero)

      let result = await sandbox.run(
        [], command: command, standardInput: try Self.pipe(text))

      #expect(
        result == CommandResult(exitStatus: 0, errorOutput: "seamerge: The patch has no changes.\n")
      )
    }
  }

  @Test(arguments: [
    (
      "diff --cc file.txt\n",
      "Cannot read the patch: line 1 starts a combined diff of a merge, which Seamerge cannot "
        + "show. Compare with one parent instead, such as with 'git diff HEAD^1'."
    ),
    (
      "--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n",
      "Cannot read the patch: the hunk at line 3 ends early. Check that the patch is complete."
    ),
    (
      "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n+c\n",
      "Cannot read the patch: the hunk at line 3 holds other lines than its header says. "
        + "Check the patch."
    ),
    (
      "1c1\n< a\n---\n> b\n",
      "Cannot read the patch: it is not a unified diff. Make one with 'git diff' or 'diff -u'."
    ),
  ])
  func patchThatCannotBeReadEndsWithTwoAndOpensNothing(text: String, message: String) async throws {
    try await withSandbox { sandbox in
      let command = sandbox.command(launcher: AppThatCannotStart(), connectionTimeout: .zero)

      let result = await sandbox.run(
        ["patch"], command: command, standardInput: try Self.pipe(text))

      #expect(result == CommandResult(exitStatus: 2, errorOutput: "seamerge: \(message)\n"))
    }
  }

  @Test func patchLargerThanARequestHoldsEndsWithTwoAndOpensNothing() async throws {
    try await withSandbox { sandbox in
      let file = try sandbox.makeFile("large.patch", text: "")
      let handle = try FileHandle(forWritingTo: file)
      try handle.truncate(atOffset: UInt64(SessionRequest.Patch.maximumByteCount + 1))
      try handle.close()
      let command = sandbox.command(launcher: AppThatCannotStart(), connectionTimeout: .zero)
      let message = "seamerge: The patch is larger than 128 MB. Split it into smaller patches.\n"

      let fromFile = await sandbox.run(["patch", "large.patch"], command: command)
      let fromInput = await sandbox.run(
        [], command: command, standardInput: StandardInput(try FileHandle(forReadingFrom: file)))

      #expect(fromFile == CommandResult(exitStatus: 2, errorOutput: message))
      #expect(fromInput == CommandResult(exitStatus: 2, errorOutput: message))
    }
  }

  @Test(arguments: [false, true])
  func patchTheAppCannotReadEndsWithTwoAndSaysSo(waits: Bool) async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .reject(.unreadablePatch))

      let result = await sandbox.run(["patch"] + (waits ? ["--wait"] : []) + ["change.patch"])

      #expect(
        result
          == CommandResult(
            exitStatus: 2,
            errorOutput:
              "seamerge: Seamerge cannot read the patch. Make one with 'git diff' or 'diff -u'.\n"))
      await app.stop()
    }
  }

  @Test(arguments: [false, true])
  func patchWhoseWindowTheAppCannotOpenEndsWithThreeAndSaysSo(waits: Bool) async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("change.patch", text: Self.patch)
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .reject(.windowNotOpened))

      let result = await sandbox.run(["patch"] + (waits ? ["--wait"] : []) + ["change.patch"])

      #expect(
        result
          == CommandResult(
            exitStatus: 3,
            errorOutput:
              "seamerge: Seamerge cannot open a window for the patch; it says why. Try again.\n"))
      await app.stop()
    }
  }

  @Test func fileOfAPatchThatCannotBeReadIsNamed() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("merge.patch", text: "diff --combined x\n")
      let command = sandbox.command(launcher: AppThatCannotStart(), connectionTimeout: .zero)

      let result = await sandbox.run(["patch", "merge.patch"], command: command)

      #expect(result.exitStatus == 2)
      #expect(result.errorOutput.hasPrefix("seamerge: Cannot read 'merge.patch': line 1 "))
    }
  }

  @Test func missingFileOfAPatchEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      let result = await sandbox.run(["patch", "none.patch"])

      let path = sandbox.directory.appending(path: "none.patch").path
      let message = "seamerge: Cannot find '\(path)'. Check the path.\n"
      #expect(result == CommandResult(exitStatus: 2, errorOutput: message))
    }
  }

  @Test func secondFileOfAPatchIsUnexpected() async throws {
    try await withSandbox { sandbox in
      let result = await sandbox.run(["patch", "a.patch", "b.patch"])

      #expect(
        result
          == CommandResult(
            exitStatus: 2,
            errorOutput: "seamerge: Unexpected argument 'b.patch'. "
              + "See 'seamerge --help'.\n"))
    }
  }

  @Test func withoutArgumentsATerminalOrDevNullShowsTheHelpAndEndsWithTwo() async throws {
    try await withSandbox { sandbox in
      let terminal = try Self.terminal()
      defer { close(terminal.primary) }
      for input in [
        StandardInput(FileHandle(fileDescriptor: terminal.secondary, closeOnDealloc: true)),
        StandardInput(try #require(FileHandle(forReadingAtPath: "/dev/null"))),
      ] {
        #expect(input.kind != .pipeOrFile)

        let result = await sandbox.run([], standardInput: input)

        #expect(result.exitStatus == 2)
        #expect(result.output.isEmpty)
        #expect(result.errorOutput.hasPrefix("Usage:\n  seamerge merge "))
        #expect(result.errorOutput.contains("seamerge patch [--wait]"))
      }
    }
  }

  /// Standard input from a pipe that holds `text` and then ends.
  private static func pipe(_ text: String) throws -> StandardInput {
    let pipe = Pipe()
    try pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    try pipe.fileHandleForWriting.close()
    return StandardInput(pipe.fileHandleForReading)
  }

  /// A new pseudo-terminal: the descriptor of its primary side and of the terminal itself.
  private static func terminal() throws -> (primary: Int32, secondary: Int32) {
    let primary = posix_openpt(O_RDWR | O_NOCTTY)
    try #require(primary >= 0)
    try #require(grantpt(primary) == 0 && unlockpt(primary) == 0)
    let name = try #require(ptsname(primary))
    let secondary = open(name, O_RDWR | O_NOCTTY)
    try #require(secondary >= 0)
    return (primary, secondary)
  }
}
