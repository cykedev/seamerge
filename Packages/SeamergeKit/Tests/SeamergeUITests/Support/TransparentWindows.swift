import AppKit
import ObjectiveC

/// The windows that the test process puts on the screen, which nobody at the screen sees.
///
/// Tests show windows as the app does, so that AppKit takes them as shown: `isVisible` says so,
/// sheets hang on them and they keep their order among each other. Each window turns fully
/// transparent and lets the mouse through as it comes onto the screen, so that it neither
/// covers the work of the person at the screen nor reacts to the pointer. A titled window cannot
/// stay off the screens instead, as AppKit moves it back onto one when it is ordered in.
///
/// No method of AppKit tells a window that it is about to be ordered in, and the code under test
/// orders its windows in itself, so the two methods every window comes onto the screen through
/// are exchanged for ones that make it transparent first. A sheet on a window that is not on the
/// screen yet brings that window there past both of them, so beginning a sheet orders such a
/// window in through them first, as AppKit would have done. Alerts that hang on a window take
/// these ways too. Not covered, as no test shows them: open and save panels, `runModal()`,
/// popovers and `setIsVisible(_:)`.
///
/// Each test target that shows windows has a copy of this file, and the copies may share a
/// process; each method is exchanged only once per process, whichever copy comes first, as a
/// second exchange would undo the first.
@MainActor
enum TransparentWindows {
  /// Turns every window transparent as it comes onto the screen, for the rest of the process.
  ///
  /// Every helper or test that can show a window calls this before.
  static func turnOn() {
    exchangeOnce(
      #selector(NSWindow.order(_:relativeTo:)),
      with: #selector(NSWindow.orderTransparently(_:relativeTo:)))
    exchangeOnce(
      #selector(NSWindow.orderFrontRegardless),
      with: #selector(NSWindow.orderFrontRegardlessTransparently))
    exchangeOnce(
      #selector(NSWindow.beginSheet(_:completionHandler:)),
      with: #selector(NSWindow.beginSheetOnTheScreen(_:completionHandler:)))
  }

  /// Exchanges the implementations of `original` and `replacement`, unless a copy of this file
  /// did already in this process: the first exchange adds a method named after `original` to
  /// `NSWindow`, which the runtime adds only once.
  private static func exchangeOnce(_ original: Selector, with replacement: Selector) {
    let marker = sel_registerName("transparentWindowsExchanged_\(NSStringFromSelector(original))")
    let mark: @convention(block) (AnyObject) -> Void = { _ in }
    guard class_addMethod(NSWindow.self, marker, imp_implementationWithBlock(mark), "v@:") else {
      return
    }
    guard let originalMethod = class_getInstanceMethod(NSWindow.self, original),
      let replacementMethod = class_getInstanceMethod(NSWindow.self, replacement)
    else {
      preconditionFailure("NSWindow has no method \(original) to exchange")
    }
    method_exchangeImplementations(originalMethod, replacementMethod)
  }
}

extension NSWindow {
  /// Makes the window transparent, then orders it as `order(_:relativeTo:)` does, whose
  /// implementation this one has exchanged with.
  @objc fileprivate func orderTransparently(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
    if place != .out {
      becomeTransparent()
    }
    orderTransparently(place, relativeTo: other)
  }

  /// Makes the window transparent, then orders it in front as `orderFrontRegardless()` does,
  /// whose implementation this one has exchanged with.
  @objc fileprivate func orderFrontRegardlessTransparently() {
    becomeTransparent()
    orderFrontRegardlessTransparently()
  }

  /// Orders the window in if it is not on the screen yet, then begins `sheet` on it as
  /// `beginSheet(_:completionHandler:)` does, whose implementation this one has exchanged with.
  @objc fileprivate func beginSheetOnTheScreen(
    _ sheet: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)?
  ) {
    if !isVisible {
      orderFront(nil)
    }
    beginSheetOnTheScreen(sheet, completionHandler: completionHandler)
  }

  private func becomeTransparent() {
    alphaValue = 0
    ignoresMouseEvents = true
  }
}
