import Foundation
import SeamergeCLI
import SessionIPC
import Synchronization
import Testing

@Suite("Exit status", .timeLimit(.minutes(1)))
struct ExitStatusTests {
  private static let merge = [
    "merge", "--local", "a.txt", "--remote", "a.txt", "--output", "a.txt",
  ]
  private static let diff = ["a.txt", "a.txt"]

  @Test func savedMergeEndsWithZero() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      #expect(await sandbox.run(Self.merge) == CommandResult(exitStatus: 0))
      await app.stop()
    }
  }

  @Test func closedComparisonEndsWithZero() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.saved))
      #expect(await sandbox.run(Self.diff) == CommandResult(exitStatus: 0))
      await app.stop()
    }
  }

  @Test(arguments: [merge, diff])
  func cancelledSessionEndsWithOne(arguments: [String]) async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .close(.cancelled))
      #expect(await sandbox.run(arguments) == CommandResult(exitStatus: 1))
      await app.stop()
    }
  }

  @Test func comparisonTheAppCannotShowEndsWithOneAndSaysSo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .reject(.unsupportedRequest))
      #expect(
        await sandbox.run(Self.diff)
          == CommandResult(
            exitStatus: 1,
            errorOutput: "seamerge: This version of Seamerge cannot compare two files yet. "
              + "Use another diff tool for now.\n"))
      await app.stop()
    }
  }

  @Test func mergeTheAppCannotShowEndsWithOneAndSaysSo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .reject(.unsupportedRequest))
      #expect(
        await sandbox.run(Self.merge)
          == CommandResult(
            exitStatus: 1,
            errorOutput: "seamerge: This version of Seamerge cannot open this merge. "
              + "Use another merge tool for now.\n"))
      await app.stop()
    }
  }

  @Test func appOfAnOlderProtocolEndsWithThreeAndSaysWhatToDo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try OlderApp(
        at: sandbox.socketURL,
        answering: #"{"event":"rejected","reason":"unsupportedVersion","version":1}"#)
      #expect(
        await sandbox.run(Self.merge)
          == CommandResult(
            exitStatus: 3,
            errorOutput: "seamerge: Seamerge cannot read the request; it may be another version. "
              + "Quit Seamerge, then try again.\n"))
      await app.stop()
    }
  }

  @Test func appThatGoesAwayBeforeTheWindowClosesEndsWithOne() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try ScriptedApp(at: sandbox.socketURL, ending: .disconnect)
      let result = await sandbox.run(Self.merge)
      #expect(result.exitStatus == 1)
      #expect(
        result.errorOutput
          == "seamerge: Lost the connection to Seamerge before the window was closed. "
          + "Run the command again.\n")
      await app.stop()
    }
  }

  @Test func appThatStopsWhileTheWindowIsOpenEndsWithOne() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let server = try SessionServer(socketURL: sandbox.socketURL)
      let (opened, openedSink) = AsyncStream.makeStream(of: Void.self)
      let app = Task {
        await server.run { connection in
          do {
            try await connection.send(.opened)
          } catch {
            Issue.record(error)
          }
          openedSink.yield()
          await connection.waitUntilDisconnected()
        }
      }
      async let result = sandbox.run(Self.merge)
      var openedWindows = opened.makeAsyncIterator()
      await openedWindows.next()
      app.cancel()
      await app.value
      #expect(await result.exitStatus == 1)
    }
  }

  @Test func appThatDoesNotAnswerEndsWithThree() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let command = sandbox.command(connectionTimeout: .milliseconds(300))
      let result = await sandbox.run(Self.merge, command: command)
      #expect(
        result
          == CommandResult(
            exitStatus: 3,
            errorOutput: "seamerge: Seamerge does not answer. Quit Seamerge, then try again.\n"))
    }
  }

  @Test func appThatCannotBeOpenedEndsWithThree() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let command = sandbox.command(launcher: AppThatCannotStart())
      let result = await sandbox.run(Self.diff, command: command)
      #expect(
        result
          == CommandResult(
            exitStatus: 3,
            errorOutput: "seamerge: Cannot open Seamerge (The application is damaged). "
              + "Open it once from the Finder, then try again.\n"))
    }
  }

  @Test func appIsOpenedBeforeTheSessionIsSent() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let launcher = CountingLauncher()
      let app = try ScriptedApp(at: sandbox.socketURL) { _ in
        launcher.count == 1 ? .close(.saved) : .close(.cancelled)
      }
      let result = await sandbox.run(Self.diff, command: sandbox.command(launcher: launcher))
      #expect(result.exitStatus == 0)
      #expect(launcher.count == 1)
      await app.stop()
    }
  }

  @Test func invalidInvocationNeitherOpensTheAppNorConnects() async throws {
    try await withSandbox { sandbox in
      let launcher = CountingLauncher()
      let result = await sandbox.run(
        ["missing.txt", "a.txt"], command: sandbox.command(launcher: launcher))
      #expect(result.exitStatus == 2)
      #expect(launcher.count == 0)
    }
  }
}

/// A launcher that counts how often the app was opened.
final class CountingLauncher: AppLauncher {
  private let openings = Mutex(0)

  var count: Int { openings.withLock { $0 } }

  func openApp() async throws {
    openings.withLock { $0 += 1 }
  }
}
