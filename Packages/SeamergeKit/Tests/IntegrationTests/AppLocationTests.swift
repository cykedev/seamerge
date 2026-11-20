import Foundation
import Testing

@testable import Integration

/// Where the running copy of the app is, and whether Git can be pointed at it.
struct AppLocationTests {
  @Test func appInDownloadsOnADiskImageOrTranslocatedCannotBeSetUp() {
    let downloads = URL(filePath: "/Users/ada/Downloads")
    func problem(_ path: String, readOnly: Bool = false, helper: Bool = true)
      -> AppLocation.Problem?
    {
      AppLocation(
        bundle: URL(filePath: path), downloads: downloads, isOnReadOnlyVolume: readOnly,
        hasHelper: helper
      ).problem
    }
    #expect(problem("/Applications/Seamerge.app") == nil)
    #expect(problem("/Users/ada/Applications/Seamerge.app") == nil)
    #expect(problem("/Users/ada/Downloads/Seamerge.app") == .temporaryPlace)
    #expect(problem("/Volumes/Seamerge/Seamerge.app", readOnly: true) == .temporaryPlace)
    #expect(
      problem("/private/var/folders/x/AppTranslocation/1234/d/Seamerge.app") == .temporaryPlace)
    #expect(problem("/Applications/Seamerge.app", helper: false) == .incomplete)
  }
}
