import AppKit
import Testing

/// That a window a test shows counts as shown for AppKit, but stays out of sight and lets the
/// pointer through, whichever way it comes onto the screen.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct TransparentWindowsTests {
  /// A way onto the screen.
  struct Way: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let show: @MainActor @Sendable (NSWindow) -> Void
  }

  nonisolated static let ways = [
    Way(testDescription: "orderFront") { $0.orderFront(nil) },
    Way(testDescription: "makeKeyAndOrderFront") { $0.makeKeyAndOrderFront(nil) },
    Way(testDescription: "orderFrontRegardless") { $0.orderFrontRegardless() },
    Way(testDescription: "orderBack") { $0.orderBack(nil) },
    Way(testDescription: "showWindow") { NSWindowController(window: $0).showWindow(nil) },
  ]

  @Test(arguments: ways) func windowOnTheScreenIsTransparent(_ way: Way) {
    TransparentWindows.turnOn()
    let window = Self.window()
    defer { window.close() }

    way.show(window)

    #expect(window.isVisible)
    #expect(window.alphaValue == 0)
    #expect(window.ignoresMouseEvents)
  }

  @Test func turningOnAgainKeepsWindowsTransparent() {
    TransparentWindows.turnOn()
    TransparentWindows.turnOn()
    let window = Self.window()
    defer { window.close() }

    window.orderFront(nil)

    #expect(window.alphaValue == 0)
  }

  @Test func sheetOnAWindowOnTheScreenIsTransparent() {
    TransparentWindows.turnOn()
    let window = Self.window()
    defer { window.close() }
    window.orderFront(nil)
    let sheet = Self.window()

    window.beginSheet(sheet)
    defer { window.endSheet(sheet) }

    #expect(sheet.isVisible)
    #expect(sheet.alphaValue == 0)
    #expect(sheet.ignoresMouseEvents)
  }

  @Test func sheetOnAWindowNotYetOnTheScreenBringsBothThereTransparent() {
    TransparentWindows.turnOn()
    let window = Self.window()
    defer { window.close() }
    let sheet = Self.window()

    window.beginSheet(sheet)
    defer { window.endSheet(sheet) }

    #expect(window.isVisible)
    #expect(window.alphaValue == 0)
    #expect(sheet.isVisible)
    #expect(sheet.alphaValue == 0)
  }

  @Test func alertOnAWindowNotYetOnTheScreenIsTransparent() {
    TransparentWindows.turnOn()
    let window = Self.window()
    defer { window.close() }
    let alert = NSAlert()
    alert.messageText = "Question"
    let shownBefore = Set(Self.shownWindows())

    alert.beginSheetModal(for: window)
    defer { window.endSheet(alert.window) }

    let shown = Self.shownWindows().filter { !shownBefore.contains($0) }
    #expect(alert.window.sheetParent === window)
    #expect(shown.contains(window))
    #expect(alert.window.isVisible)
    #expect(shown.allSatisfy { $0.alphaValue == 0 }, "\(shown.map { ($0, $0.alphaValue) })")
  }

  @Test func windowsKeepTheirOrderAndLeaveTheScreenAsBefore() {
    TransparentWindows.turnOn()
    let first = Self.window()
    let second = Self.window()
    defer {
      first.close()
      second.close()
    }

    first.orderFront(nil)
    second.orderFront(nil)
    #expect(second.orderedIndex < first.orderedIndex)
    second.orderOut(nil)

    #expect(!second.isVisible)
    #expect(first.isVisible)
  }

  /// The windows of the process that are on the screen.
  private static func shownWindows() -> [NSWindow] {
    NSApplication.shared.windows.filter(\.isVisible)
  }

  private static func window() -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    return window
  }
}
