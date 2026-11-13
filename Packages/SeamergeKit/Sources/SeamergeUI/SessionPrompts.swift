import AppKit
import MergeModel

/// What the user chose when asked about saving with open conflicts.
enum OpenConflictsChoice {
  /// Not to save, and to go to the next open conflict instead.
  case goToNextConflict

  /// To save with conflict markers in place of the open conflicts.
  case saveWithMarkers

  /// Not to save.
  case cancel
}

/// What the user chose when asked about closing a window with unsaved changes.
enum UnsavedChangesChoice {
  /// To save, then close.
  case save

  /// To close without saving.
  case discard

  /// Not to close.
  case cancel
}

/// What a window asks or tells the user before it discards work, while it saves, and when it
/// cannot switch to another comparison.
///
/// A window shows them as sheets; the window takes the prompts when it is made.
@MainActor
protocol SessionPrompts: AnyObject {
  /// Asks whether to save although `count` conflicts are open; `gitTakesItAsResolved` says
  /// that Git waits for the file and takes it as resolved once it is saved.
  func confirmSavingWithOpenConflicts(
    _ count: Int, gitTakesItAsResolved: Bool, in window: NSWindow
  ) async -> OpenConflictsChoice

  /// Asks whether to save the changes of the result of `name` before the window closes; a merge
  /// that `caller` waits for names its open conflicts, `openConflictCount`, and, if it is Git,
  /// what Git does.
  func confirmClosing(
    _ name: String, openConflictCount: Int, caller: WaitingCaller?, in window: NSWindow
  ) async -> UnsavedChangesChoice

  /// Asks whether to leave the merge of `name` unresolved although `count` decisions would be
  /// lost, and tells whether to; `gitPutsBackTheFile` says that Git waits and restores its file.
  func confirmLeavingUnresolved(
    _ name: String, discarding count: Int, gitPutsBackTheFile: Bool, in window: NSWindow
  ) async -> Bool

  /// Tells that `encoding` cannot hold the result of `name` and asks whether to save it in UTF-8.
  func offerUTF8(saving name: String, in encoding: FileEncoding, in window: NSWindow) async -> Bool

  /// Tells that the result of `name` could not be saved, and why.
  func reportFailedSaving(_ name: String, reason: String, in window: NSWindow) async

  /// Asks where to save the result, suggesting `name`, and returns the place or `nil`.
  func chooseDestination(suggesting name: String, in window: NSWindow) async -> URL?

  /// Tells that another app changed the result file `name` and asks whether to reload it.
  func confirmReloadingChangedResult(_ name: String, in window: NSWindow) async -> Bool

  /// Asks whether to reload the files that changed on disk although `count` decisions would be
  /// lost; `name` names the one that changed, or is `nil` if more than one did.
  func confirmReloading(_ name: String?, discarding count: Int, in window: NSWindow) async -> Bool

  /// Asks whether to change the files although `count` decisions would be lost.
  func confirmChangingFiles(discarding count: Int, in window: NSWindow) async -> Bool

  /// Asks whether to switch although `count` decisions would be lost, and tells whether to.
  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool

  /// Asks whether to reset every decision although it discards the text typed by hand in
  /// `count` blocks, and tells whether to.
  func confirmResettingAll(discardingHandwritingIn count: Int, in window: NSWindow) async -> Bool

  /// Tells that the files could not be compared anew.
  func reportFailedComparison(in window: NSWindow) async
}

/// The prompts of a window as sheets.
@MainActor
final class SessionSheets: SessionPrompts {
  func confirmDiscarding(_ count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "The switch discards \(count) decisions.", bundle: .module,
      comment: "Sheet before switching the comparison, such as The switch discards 3 decisions.")
    Self.addDefaultCancelButton(to: alert)
    alert.addButton(
      withTitle: String(localized: "Switch", bundle: .module, comment: "Button: switch anyway."))
    return await Self.confirm(alert, in: window)
  }

  func confirmResettingAll(discardingHandwritingIn count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "This discards handwritten text in \(count) blocks.", bundle: .module,
      comment: "Sheet before resetting every decision, such as in 3 blocks.")
    Self.addDefaultCancelButton(to: alert)
    alert.addButton(
      withTitle: String(
        localized: "Reset", bundle: .module,
        comment:
          "Resetting decisions: the button of the sheet before resetting every one, and the submenu of a context menu with the ways to reset."
      ))
    return await Self.confirm(alert, in: window)
  }

  func confirmSavingWithOpenConflicts(
    _ count: Int, gitTakesItAsResolved: Bool, in window: NSWindow
  ) async -> OpenConflictsChoice {
    let alert = NSAlert()
    alert.messageText = SessionToolbar.countText(openConflictCount: count, hasConflicts: true)
    alert.informativeText =
      gitTakesItAsResolved
      ? String(
        localized:
          "Open conflicts are written as conflict markers. Git then treats the file as resolved.",
        bundle: .module, comment: "Sheet before saving with open conflicts that Git waits for.")
      : String(
        localized: "Open conflicts are written as conflict markers.", bundle: .module,
        comment: "Sheet before saving with open conflicts outside Git.")
    for title in [
      String(
        localized: "Go to Next Conflict", bundle: .module,
        comment: "Button of the sheet before saving with open conflicts: do not save, go on."),
      String(
        localized: "Save with Markers", bundle: .module,
        comment: "Button of the sheet before saving with open conflicts: save anyway."),
      Self.cancelTitle,
    ] {
      alert.addButton(withTitle: title)
    }
    return switch await Self.present(alert, in: window) {
    case .alertFirstButtonReturn: .goToNextConflict
    case .alertSecondButtonReturn: .saveWithMarkers
    default: .cancel
    }
  }

  func confirmClosing(
    _ name: String, openConflictCount: Int, caller: WaitingCaller?, in window: NSWindow
  ) async -> UnsavedChangesChoice {
    let alert = NSAlert()
    if let caller {
      alert.messageText = String(
        localized: "Do you want to save the merge of “\(name)”?", bundle: .module,
        comment: "Sheet before closing a merge that a command waits for, with unsaved changes.")
      let consequence =
        caller == .git
        ? String(
          localized:
            "If you don’t save, your decisions are lost and Git keeps the file unresolved.",
          bundle: .module, comment: "Sheet before closing a merge that Git waits for: what follows."
        )
        : String(
          localized: "If you don’t save, your decisions are lost.", bundle: .module,
          comment:
            "Sheet before closing a merge that a command other than Git waits for: what follows.")
      alert.informativeText =
        openConflictCount > 0
        ? String(
          localized: "\(openConflictCount) conflicts are still open. \(consequence)",
          bundle: .module,
          comment:
            "Sheet before closing a merge that a command waits for, such as 2 conflicts are still open. If you don’t save…"
        ) : consequence
    } else {
      alert.messageText = String(
        localized: "Do you want to save the changes made to the document “\(name)”?",
        bundle: .module, comment: "Sheet before closing a merge of files with unsaved changes.")
      alert.informativeText = String(
        localized: "Your changes will be lost if you don’t save them.", bundle: .module,
        comment: "Sheet before closing a merge of files with unsaved changes: what follows.")
    }
    alert.addButton(
      withTitle: SessionCommand.save.title)
    let discard = alert.addButton(
      withTitle: String(
        localized: "Don’t Save", bundle: .module, comment: "Button: close without saving."))
    discard.keyEquivalent = "d"
    discard.keyEquivalentModifierMask = .command
    alert.addButton(withTitle: Self.cancelTitle)
    return switch await Self.present(alert, in: window) {
    case .alertFirstButtonReturn: .save
    case .alertSecondButtonReturn: .discard
    default: .cancel
    }
  }

  func confirmLeavingUnresolved(
    _ name: String, discarding count: Int, gitPutsBackTheFile: Bool, in window: NSWindow
  ) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Leave “\(name)” unresolved?", bundle: .module,
      comment: "Sheet before leaving a merge unresolved that has decisions.")
    alert.informativeText =
      gitPutsBackTheFile
      ? String(
        localized:
          "Git puts the file back as it was before Seamerge opened it, with its conflict markers. Your decisions in \(count) blocks are lost.",
        bundle: .module,
        comment:
          "Sheet before leaving a merge unresolved: Git restores the file it had before the merge tool, such as in 3 blocks."
      )
      : String(
        localized: "Your decisions in \(count) blocks are lost.", bundle: .module,
        comment:
          "Sheet before leaving a merge unresolved that a command other than Git waits for, such as in 3 blocks."
      )
    Self.addDefaultCancelButton(to: alert)
    alert.addButton(withTitle: SessionCommand.leaveUnresolved.title)
    return await Self.confirm(alert, in: window)
  }

  func offerUTF8(saving name: String, in encoding: FileEncoding, in window: NSWindow) async -> Bool
  {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "“\(name)” can’t be saved in \(encoding.name).", bundle: .module,
      comment: "Sheet: the result holds characters the encoding lacks, such as in ISO 8859-1.")
    alert.informativeText = String(
      localized: "Some of its characters don’t exist in \(encoding.name). UTF-8 holds them all.",
      bundle: .module, comment: "Sheet: the result holds characters the encoding lacks.")
    alert.addButton(
      withTitle: String(
        localized: "Save as UTF-8", bundle: .module, comment: "Button: save in UTF-8 instead."))
    alert.addButton(withTitle: Self.cancelTitle)
    return await Self.present(alert, in: window) == .alertFirstButtonReturn
  }

  func reportFailedSaving(_ name: String, reason: String, in window: NSWindow) async {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Couldn’t Save “\(name)”", bundle: .module, comment: "Sheet after saving failed.")
    alert.informativeText = String(
      localized: "\(reason) The file is unchanged, and the window keeps your work.",
      bundle: .module, comment: "Sheet after saving failed: the reason, then what still holds.")
    _ = await Self.present(alert, in: window)
  }

  func chooseDestination(suggesting name: String, in window: NSWindow) async -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    guard await panel.beginSheetModal(for: window) == .OK else { return nil }
    return panel.url
  }

  func confirmReloadingChangedResult(_ name: String, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "“\(name)” was changed by another app.", bundle: .module,
      comment: "Sheet: another app changed the file the result is saved to.")
    alert.informativeText = String(
      localized:
        "Keep your version to save over it later, or reload the file as it is now. You can undo reloading.",
      bundle: .module, comment: "Sheet: another app changed the result file; the choices.")
    alert.addButton(
      withTitle: String(
        localized: "Keep My Version", bundle: .module,
        comment: "Button: keep the result of the window and ignore the change on disk."))
    alert.addButton(withTitle: Self.reloadTitle)
    return await Self.present(alert, in: window) == .alertSecondButtonReturn
  }

  func confirmReloading(_ name: String?, discarding count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText =
      name.map {
        String(
          localized: "\($0) changed on disk. Reloading discards \(count) decisions.",
          bundle: .module,
          comment:
            "Sheet before reloading a changed file, with the name of its side, such as main changed on disk. Reloading discards 3 decisions."
        )
      }
      ?? String(
        localized: "The files changed on disk. Reloading discards \(count) decisions.",
        bundle: .module, comment: "Sheet before reloading more than one changed file.")
    Self.addDefaultCancelButton(to: alert)
    alert.addButton(withTitle: Self.reloadTitle)
    return await Self.confirm(alert, in: window)
  }

  func confirmChangingFiles(discarding count: Int, in window: NSWindow) async -> Bool {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Changing the files discards \(count) decisions.", bundle: .module,
      comment: "Sheet before showing other files in a window, such as discards 3 decisions.")
    Self.addDefaultCancelButton(to: alert)
    alert.addButton(
      withTitle: String(
        localized: "Change", bundle: .module,
        comment: "Sheet Change Files: the default button, which shows the files in the window."))
    return await Self.confirm(alert, in: window)
  }

  /// Adds Cancel as the first button, which keeps what would be lost and is the default one.
  ///
  /// An alert gives a button named Cancel the Escape key and no button Return, so Cancel gets
  /// Return here; ``present(_:in:)`` answers Escape with Cancel as well.
  private static func addDefaultCancelButton(to alert: NSAlert) {
    let cancel = alert.addButton(withTitle: cancelTitle)
    cancel.keyEquivalent = "\r"
  }

  /// Shows `alert`, whose first button is Cancel and the default one, as a sheet of `window`, and
  /// tells whether the user pressed the second button.
  private static func confirm(_ alert: NSAlert, in window: NSWindow) async -> Bool {
    await present(alert, in: window) == .alertSecondButtonReturn
  }

  /// Shows `alert` as a sheet of `window` and returns the button pressed; Escape and
  /// Command-Period press its Cancel button, if it has one.
  ///
  /// An alert gives Escape only to a Cancel button that does not hold Return, and Command-Period
  /// to none, so the sheet watches for both while it is open.
  private static func present(
    _ alert: NSAlert, in window: NSWindow
  ) async -> NSApplication.ModalResponse {
    let cancelTitle = cancelTitle
    let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.window === alert.window, isCancelKey(event),
        let cancel = alert.buttons.first(where: { $0.title == cancelTitle })
      else { return event }
      cancel.performClick(nil)
      return nil
    }
    defer {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }
    return await alert.beginSheetModal(for: window)
  }

  /// Whether `event` is Escape or Command-Period, the keys that cancel a sheet.
  static func isCancelKey(_ event: NSEvent) -> Bool {
    let escapeKeyCode: UInt16 = 53
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return event.keyCode == escapeKeyCode && modifiers.isEmpty
      || event.charactersIgnoringModifiers == "." && modifiers == .command
  }

  private static var cancelTitle: String {
    String(localized: "Cancel", bundle: .module, comment: "Button: close the sheet and do nothing.")
  }

  private static var reloadTitle: String {
    SessionWindowController.reloadName
  }

  func reportFailedComparison(in window: NSWindow) async {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Couldn’t Compare the Files Anew", bundle: .module,
      comment: "Sheet after switching the comparison failed.")
    alert.informativeText = String(
      localized: "The window still shows the previous comparison.", bundle: .module,
      comment: "Sheet after switching the comparison failed: what happens next.")
    _ = await Self.present(alert, in: window)
  }
}
