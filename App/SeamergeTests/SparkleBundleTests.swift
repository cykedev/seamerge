import AppKit
import Testing

/// How the built app carries Sparkle: its settings in the information of the app, its texts in
/// English only, and its license in the credits.
@MainActor
struct SparkleBundleTests {
  @Test func infoOfTheAppNamesASecureFeedAndTurnsOffProfileAndInstallsWithoutAClick() throws {
    let info = try #require(
      NSDictionary(contentsOf: try builtApp().appending(path: "Contents/Info.plist")))

    let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
    #expect(feed.scheme == "https")
    #expect(feed.host() == "www.seamerge.app")
    #expect(info["SUEnableSystemProfiling"] as? Bool == false)
    #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
    #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
    let key = try #require((info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) })
    #expect(key.count == 32)
  }

  @Test func builtAppKeepsNoTranslationOfSparkleButItsEnglish() throws {
    let resources = try builtApp().appending(
      path: "Contents/Frameworks/Sparkle.framework/Versions/B/Resources")

    let folders = try FileManager.default.contentsOfDirectory(atPath: resources.path)
      .filter { $0.hasSuffix(".lproj") }

    #expect(folders == ["Base.lproj"])
  }

  @Test func creditsHoldTheLicenseOfSparkleWithItsExternalLicenses() throws {
    let credits = try NSAttributedString(
      url: try builtApp().appending(path: "Contents/Resources/Credits.rtf"), options: [:],
      documentAttributes: nil
    ).string

    for passage in [
      "Copyright (c) 2006-2013 Andy Matuschak.", "Copyright (c) 2011-2014 Kornel Lesiński.",
      "Permission is hereby granted, free of charge,", "EXTERNAL LICENSES",
      "Copyright 2003-2005 Colin Percival", "Copyright (c) 2008-2010 Yuta Mori",
      "Copyright (c) 2015 Orson Peters", "Copyright (c) 2011 Mark Hamlin.",
    ] {
      #expect(credits.contains(passage), "\(passage)")
    }
  }

  /// The app that the scheme builds next to the tests.
  private func builtApp() throws -> URL {
    let app = Bundle(for: AppDelegate.self).bundleURL.deletingLastPathComponent()
      .appending(path: "Seamerge.app")
    try #require(FileManager.default.fileExists(atPath: app.path), "No app at \(app.path)")
    return app
  }
}
