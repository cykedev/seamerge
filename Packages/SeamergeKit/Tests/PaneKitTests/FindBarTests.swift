import AppKit
import PaneKit
import Testing

/// Checks the find bar of a single pane, which AppKit shows below its text where no search over
/// several panes takes its place, with lines that run beyond the pane and with lines that wrap.
///
/// The finder keeps its search text on the find pasteboard of the system, which every app
/// shares; each test puts back what it held, whether the test passes or not.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct FindBarTests {
  @Test(arguments: [false, true])
  func textKeepsItsSizeWhileTheFindBarIsOpenAndAfterwards(wrapsLines: Bool) async {
    await FindPasteboard.preserving {
      let (pane, window) = Self.pane(wrapsLines: wrapsLines)
      defer { window.close() }
      let textView = pane.documentView
      let size = textView.frame.size
      if wrapsLines {
        // Each line takes several screen lines.
        #expect(size.height > 2_000 * pane.theme.rowHeight)
      } else {
        #expect(size.height == 1_000 * pane.theme.rowHeight)
        #expect(size.width > textView.visibleRect.width)
      }

      Self.perform(.showFindInterface, in: pane)
      #expect(textView.enclosingScrollView?.isFindBarVisible == true)
      #expect(textView.frame.size == size)
      pane.layoutSubtreeIfNeeded()
      #expect(textView.frame.size == size)

      Self.perform(.hideFindInterface, in: pane)
      #expect(textView.enclosingScrollView?.isFindBarVisible == false)
      #expect(textView.frame.size == size)
    }
  }

  @Test(arguments: [false, true])
  func findNextBringsAMatchOutsideTheViewIntoViewWhileTheFindBarIsOpen(wrapsLines: Bool) async {
    await FindPasteboard.preserving {
      let (pane, window) = Self.pane(wrapsLines: wrapsLines)
      defer { window.close() }
      let textView = pane.documentView
      let pasteboard = NSPasteboard(name: .find)
      pasteboard.clearContents()
      pasteboard.setString("row800 ", forType: .string)

      Self.perform(.showFindInterface, in: pane)
      window.makeFirstResponder(textView)
      Self.perform(.nextMatch, in: pane)

      let match = NSRange(location: CodeRows.start(ofRow: 800, length: Self.length) + 4, length: 7)
      #expect(textView.selectedRange() == match)
      let onScreen = textView.firstRect(forCharacterRange: match, actualRange: nil)
      let place = textView.convert(window.convertFromScreen(onScreen), from: nil)
      #expect(textView.visibleRect.contains(place))
    }
  }

  private static let length = 300

  /// A pane of a thousand lines, each wider than the pane, in a key window with the focus in its
  /// text.
  private static func pane(wrapsLines: Bool) -> (PaneView, NSWindow) {
    let pane = PaneView()
    pane.wrapsLines = wrapsLines
    pane.content = CodeRows.content(count: 1_000, length: length)
    let window = Rendering.host(pane, size: CGSize(width: 500, height: 300), isKey: true)
    window.makeFirstResponder(pane.documentView)
    return (pane, window)
  }

  /// Carries out `action` of the finder in the text of `pane`, as its menu item does.
  private static func perform(_ action: NSTextFinder.Action, in pane: PaneView) {
    let item = NSMenuItem(
      title: "", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "")
    item.tag = action.rawValue
    pane.documentView.performTextFinderAction(item)
  }
}
