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
}
