import AppKit
import PaneKit
import Testing

@testable import SeamergeUI

/// Drives the find bar of a session window as the user does: types into its fields and waits
/// for the matches, which the finder finds on a thread of its own and hands over on the main
/// queue.
///
/// The driver hears what the window tells VoiceOver, which it says once the matches change.
@MainActor
final class SearchDriver {
  let controller: SessionWindowController

  /// What the window told VoiceOver, in order.
  private(set) var announcements: [String] = []

  /// A test waiting for a condition on the matches, with what resumes it.
  private var waiter: (condition: () -> Bool, continuation: CheckedContinuation<Void, Never>)?

  init(_ controller: SessionWindowController) {
    self.controller = controller
    controller.presentation.announce = { [weak self] text in
      self?.announcements.append(text)
      self?.matchesMayHaveChanged()
    }
  }

  var search: PaneSearch { controller.presentation.search }

  /// The search field of the find bar.
  var searchField: NSSearchField {
    get throws {
      let bar = try #require(search.findBar.findBarView)
      return try #require(Self.views(in: bar).compactMap { $0 as? NSSearchField }.first)
    }
  }

  /// The field for the text that replaces a match.
  var replaceField: NSTextField {
    get throws {
      let bar = try #require(search.findBar.findBarView)
      let fields = Self.views(in: bar).compactMap { $0 as? NSTextField }
      return try #require(
        fields.first { !($0 is NSSearchField) && $0.isEditable && !$0.isHidden })
    }
  }

  /// Carries out `command` as its menu item does, along the responder chain from the focus of
  /// the window, and tells whether anything along it carried it out.
  @discardableResult
  func send(_ command: SessionCommand) throws -> Bool {
    let window = try #require(controller.window)
    holdSearchText()
    let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
    let responder = window.firstResponder ?? window
    return responder.tryToPerform(command.action, with: item)
  }

  /// Carries out `action` of the finder, as a button of the find bar does.
  func perform(_ action: NSTextFinder.Action) {
    holdSearchText()
    search.perform(action)
  }

  /// Puts the text of the search field back on the find pasteboard of the system, which Find
  /// Next and Replace read: another test run may have written to it since the user typed.
  private func holdSearchText() {
    guard let bar = search.findBar.findBarView,
      let text = Self.views(in: bar).compactMap({ $0 as? NSSearchField }).first?.stringValue,
      !text.isEmpty
    else { return }
    let pasteboard = NSPasteboard(name: .find)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// Types `text` into the search field as the user would, over all it held.
  ///
  /// The finder may still search for what the field held before, and its matches may come after
  /// the typing; a test that waits for the matches of `text` tells them apart by their places.
  func type(_ text: String) throws {
    try type(text, into: searchField)
  }

  /// Types `text` into the field for the text that replaces a match, over all it held.
  func typeReplacement(_ text: String) throws {
    try type(text, into: replaceField)
  }

  private func type(_ text: String, into field: NSTextField) throws {
    let window = try #require(controller.window)
    if (window.firstResponder as? NSText)?.delegate as? NSTextField !== field {
      window.makeFirstResponder(field)
    }
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.selectAll(nil)
    editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(field.stringValue == text)
  }

  /// Returns once the search has found `count` matches, or once the test is cancelled.
  func waitForMatches(count: Int) async {
    await waitForMatches { [search] in search.matches.count == count }
  }

  /// Returns once `condition` holds after a change of the matches, or once the test is
  /// cancelled, as when it runs out of time.
  func waitForMatches(until condition: @escaping () -> Bool) async {
    guard !condition() else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiter = (condition, continuation)
      }
    } onCancel: {
      Task { @MainActor in self.resumeWaiter() }
    }
  }

  private func matchesMayHaveChanged() {
    guard let waiter, waiter.condition() else { return }
    resumeWaiter()
  }

  private func resumeWaiter() {
    let continuation = waiter?.continuation
    waiter = nil
    continuation?.resume()
  }

  private static func views(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(views(in:))
  }
}
