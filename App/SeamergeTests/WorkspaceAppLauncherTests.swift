import Foundation
import Testing

/// The helper finds the app it is part of, wherever the app lies and however the helper is
/// started.
struct WorkspaceAppLauncherTests {
  @Test func helperFindsTheAppAroundItself() {
    let helper = URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge")

    #expect(
      WorkspaceAppLauncher(executableURL: helper).appURL
        == URL(filePath: "/Applications/Seamerge.app", directoryHint: .isDirectory))
  }

  @Test func helperStartedThroughALinkFindsTheAppOfTheLinkedFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "Launcher-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: folder)
      } catch {
        Issue.record(error, "The folder of the test could not be removed")
      }
    }
    let helpers = folder.appending(path: "My Apps/Seamerge.app/Contents/Helpers")
    try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
    let helper = helpers.appending(path: "seamerge")
    try Data().write(to: helper)
    let link = folder.appending(path: "seamerge")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)

    let appURL = WorkspaceAppLauncher(executableURL: link).appURL

    #expect(
      appURL.standardizedFileURL
        == helpers.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        .standardizedFileURL)
  }

  @Test(.timeLimit(.minutes(1))) func helperOfTheBuiltAppRunsThroughALinkElsewhere() throws {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "Launcher-\(UUID().uuidString)/usr local/bin", directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: folder.deletingLastPathComponent())
      } catch {
        Issue.record(error, "The folder of the test could not be removed")
      }
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let app = Bundle(for: AppDelegate.self).bundleURL.deletingLastPathComponent()
      .appending(path: "Seamerge.app")
    let link = folder.appending(path: "seamerge")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: app.appending(path: "Contents/Helpers/seamerge"))
    let process = Process()
    process.executableURL = link
    process.arguments = ["--version"]
    let output = Pipe()
    process.standardOutput = output
    process.standardInput = FileHandle.nullDevice

    try process.run()
    let printed = String(
      decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    let version = try #require(
      Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String)
    #expect(process.terminationStatus == 0)
    #expect(printed.contains(version))
  }

  @Test(.timeLimit(.minutes(1))) func waitingForAProcessThatEndsSaysItEnded() async throws {
    let process = try Self.sleep(seconds: "0.2")
    #expect(
      await WorkspaceAppLauncher.waitUntilProcessEnds(
        process.processIdentifier, within: .seconds(20)))
    process.waitUntilExit()
  }

  @Test(.timeLimit(.minutes(1))) func waitingForAProcessThatGoesOnEndsAtTheTimeout() async throws {
    let process = try Self.sleep(seconds: "30")
    defer { process.terminate() }
    let clock = ContinuousClock()
    let start = clock.now

    let hasEnded = await WorkspaceAppLauncher.waitUntilProcessEnds(
      process.processIdentifier, within: .milliseconds(200))

    #expect(!hasEnded)
    #expect(clock.now - start < .seconds(10))
  }

  @Test(.timeLimit(.minutes(1))) func waitingForAProcessThatHasEndedReturnsAtOnce() async throws {
    let process = try Self.sleep(seconds: "0")
    process.waitUntilExit()
    #expect(
      await WorkspaceAppLauncher.waitUntilProcessEnds(
        process.processIdentifier, within: .seconds(20)))
  }

  private static func sleep(seconds: String) throws -> Process {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sleep")
    process.arguments = [seconds]
    try process.run()
    return process
  }
}
