import AppKit

/// What the app shows and does around its windows: alerts that say what went wrong and what to
/// do, hiding itself, and coming to the front.
@MainActor
protocol AppPresenter: AnyObject {
  /// Shows `error` with what to do next.
  func present(_ error: any Error)

  /// Hides the app, so that the app before it is in front again.
  func hide()

  /// Brings the app to the front, as a service that opens a window does.
  func activate()
}

/// The presenter of the running app.
final class ApplicationPresenter: AppPresenter {
  func present(_ error: any Error) {
    NSApplication.shared.presentError(error)
  }

  func hide() {
    NSApplication.shared.hide(nil)
  }

  func activate() {
    NSApplication.shared.activate()
  }
}
