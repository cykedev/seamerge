import AppKit
import FolderCompareTestSupport
import Testing

@testable import FolderCompare
@testable import SeamergeUI

/// That every helper that makes a window turns off the animations of windows, so that a test that
/// shows a window while the screen is locked holds no thread.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct WindowAnimationsTests {
  @Test func turningThemOffChangesWhatAppKitReads() {
    WindowAnimations.turnOff()
    #expect(WindowAnimations.areOff)
    #expect(UserDefaults.standard.object(forKey: WindowAnimations.settingKey) as? Bool == false)
  }

  @Test func aWindowForASessionTurnsThemOff() async throws {
    let session = try await SampleDiffs.greeting()
    try await expectTurnedOff { _ = try Windows.controller(for: session) }
  }

  @Test func aPictureOfASessionTurnsThemOffBeforeItsPreparation() async throws {
    let session = try await SampleDiffs.greeting()
    var wereOff = false
    try await expectTurnedOff {
      try Windows.picture(
        session, context: SampleDiffs.gitContext, look: .light, named: "window-animations"
      ) { _ in wereOff = WindowAnimations.areOff }
    }
    #expect(wereOff)
  }

  @Test func aWindowForACollectionTurnsThemOff() async throws {
    let collection = FileCollection(
      files: try SampleCollections.commit(in: try SampleCollections.folder()))
    try await expectTurnedOff { _ = try await Windows.controller(for: collection) }
  }

  @Test func theWelcomeWindowTurnsThemOff() async throws {
    try await expectTurnedOff { _ = try WelcomeFixture() }
  }

  @Test func preparingAWindowForAPictureTurnsThemOff() async throws {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    try await expectTurnedOff {
      Rendering.prepare(
        window, size: CGSize(width: 200, height: 100), appearance: Look.light.appearance)
    }
  }

  /// Expects `makeWindow` to turn the animations of windows off after they were on again, as at
  /// the start of the process; they stay off afterwards.
  private func expectTurnedOff(_ makeWindow: () async throws -> Void) async throws {
    WindowAnimations.arguments[WindowAnimations.settingKey] = nil
    defer { WindowAnimations.turnOff() }
    try #require(!WindowAnimations.areOff)
    try await makeWindow()
    #expect(WindowAnimations.areOff)
  }
}
