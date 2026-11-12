import AppKit
import Testing

/// Clicks views the way the mouse does.
///
/// Only for views that do not track the mouse: a tracking loop runs the main queue while it waits
/// for the button to go up, which lets the test run report and end in the middle of a test.
@MainActor
enum Clicking {
  /// Presses the primary button at `point` of `view`, which lies in a window.
  static func click(_ view: NSView, at point: CGPoint) throws {
    let window = try #require(view.window)
    view.mouseDown(with: try event(.leftMouseDown, at: view.convert(point, to: nil), in: window))
  }

  /// The menu that a secondary click at `point` of `view` opens.
  static func menu(of view: NSView, at point: CGPoint) throws -> NSMenu? {
    let window = try #require(view.window)
    return view.menu(
      for: try event(.rightMouseDown, at: view.convert(point, to: nil), in: window))
  }

  private static func event(
    _ type: NSEvent.EventType, at location: CGPoint, in window: NSWindow
  ) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1))
  }
}
