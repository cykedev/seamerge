import Foundation
import SessionIPC
import Testing

/// Where the app listens: on the default socket, unless its launch names another folder.
///
/// That AppKit reads `-SessionSocketDirectory <path>` from the launch is checked by the step "app
/// launches" of `Scripts/check.sh`, which looks for the socket in the folder it names.
struct SessionSocketLaunchTests {
  @Test func launchWithoutAFolderListensOnTheDefaultSocket() {
    #expect(SessionSocket.url(launchedWith: [:]) == SessionSocket.defaultURL)
    #expect(
      SessionSocket.url(launchedWith: ["SUEnableAutomaticChecks": "NO"]) == SessionSocket.defaultURL
    )
    #expect(
      SessionSocket.url(launchedWith: [SessionSocket.directoryArgument: ""])
        == SessionSocket.defaultURL)
  }

  @Test func launchWithAFolderListensInIt() {
    let url = SessionSocket.url(launchedWith: [
      SessionSocket.directoryArgument: "/private/tmp/sm.check"
    ])

    #expect(url == URL(filePath: "/private/tmp/sm.check/seamerge.sock"))
  }
}
