import Foundation
import SeamergeCLI
import SessionIPC
import Testing

/// A command that meets a copy of the app on its way out waits for it and gets its window from
/// the next copy, instead of ending without a window and without a word.
@Suite("An app that quits", .timeLimit(.minutes(1)))
struct QuittingAppTests {
  private static let diff = ["a.txt", "a.txt"]

  @Test func comparisonRefusedByAQuittingAppOpensInTheNextCopy() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try RestartingApp(at: sandbox.socketURL, quitting: true)

      let result = await sandbox.run(Self.diff, command: sandbox.command(launcher: app))

      #expect(result == CommandResult(exitStatus: 0))
      #expect(await app.copiesThatShowedAWindow == 1)
      await app.quit()
    }
  }

  @Test func appThatDoesNotQuitInTimeEndsTheCommandWithThreeAndSaysSo() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try RestartingApp(at: sandbox.socketURL, quitting: true, hangsWhileQuitting: true)

      let result = await sandbox.run(Self.diff, command: sandbox.command(launcher: app))

      #expect(
        result
          == CommandResult(
            exitStatus: 3,
            errorOutput: "seamerge: Seamerge is still quitting. Wait until it has quit, "
              + "or force it to quit, then try again.\n"))
      await app.quit()
    }
  }

  @Test func comparisonAfterTheAppStoppedListeningOpensInTheNextCopy() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try RestartingApp(at: sandbox.socketURL, quitting: false)

      let result = await sandbox.run(Self.diff, command: sandbox.command(launcher: app))

      #expect(result == CommandResult(exitStatus: 0))
      #expect(await app.openings == 2)
      #expect(await app.copiesThatShowedAWindow == 1)
      await app.quit()
    }
  }

  @Test func laterFileOfARunRefusedByAQuittingAppOpensInTheNextCopy() async throws {
    try await withSandbox { sandbox in
      try sandbox.makeFile("a.txt")
      let app = try RestartingApp(at: sandbox.socketURL, quitting: true)
      var environment = sandbox.environment
      environment["GIT_DIFF_PATH_COUNTER"] = "2"
      environment["GIT_DIFF_PATH_TOTAL"] = "3"

      let result = await sandbox.command(launcher: app).run(
        ["diff", "--collect", "--path", "a.txt", "a.txt", "a.txt"],
        standardInput: StandardInput(.nullDevice), workingDirectory: sandbox.directory,
        environment: environment)

      #expect(result == CommandResult(exitStatus: 0))
      #expect(await app.copiesThatShowedAWindow == 1)
      await app.quit()
    }
  }
}

/// An app whose copy at hand is on its way out: it refuses sessions as quitting, or it no longer
/// listens at all. The next time the command opens the app after that copy has gone, a new copy
/// starts and closes the window of every session as saved.
private actor RestartingApp: AppLauncher {
  private let socketURL: URL
  private var copy: Task<Void, Never>?
  private var hasQuit = false
  private let hangsWhileQuitting: Bool

  /// How often the command opened the app.
  private(set) var openings = 0

  /// How many copies started after the one on its way out.
  private(set) var copiesThatShowedAWindow = 0

  /// Creates the app with a copy that refuses sessions as quitting, or with one that no longer
  /// listens and has gone by the second time the command opens the app.
  init(at socketURL: URL, quitting: Bool, hangsWhileQuitting: Bool = false) throws {
    self.socketURL = socketURL
    self.hangsWhileQuitting = hangsWhileQuitting
    copy = quitting ? try Self.startCopy(at: socketURL, answering: .rejected(.quitting)) : nil
  }

  func openApp() async throws {
    openings += 1
    guard copy == nil, hasQuit || openings > 1 else { return }
    copiesThatShowedAWindow += 1
    copy = try Self.startCopy(at: socketURL, answering: .closed(.saved))
  }

  func waitUntilAppQuits(within timeout: Duration) async -> Bool {
    guard !hangsWhileQuitting else { return false }
    await quit()
    hasQuit = true
    return true
  }

  /// Stops the copy that runs.
  func quit() async {
    copy?.cancel()
    await copy?.value
    copy = nil
  }

  private static func startCopy(at url: URL, answering event: SessionEvent) throws -> Task<
    Void, Never
  > {
    let server = try SessionServer(socketURL: url)
    return Task {
      await server.run { connection in
        do {
          if case .closed = event {
            try await connection.send(.opened)
          }
          try await connection.send(event)
        } catch {
          Issue.record(error, "The app in the test could not answer")
        }
      }
    }
  }
}
