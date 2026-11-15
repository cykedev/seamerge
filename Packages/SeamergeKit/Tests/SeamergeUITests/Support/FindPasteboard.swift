import AppKit

/// The find pasteboard of the system, which the finder of a find bar writes its search text to.
///
/// Find Next and Replace read the search text from it, and every app shares it: another app or
/// test run that writes to it while a test runs, as Use Selection for Find elsewhere does, makes
/// the test search for something else. Tests that use the find bar must not run in two
/// processes at once.
@MainActor
enum FindPasteboard {
  /// Runs `body` with an empty find pasteboard and then puts back what it held before, also if
  /// `body` fails, once what `body` made, its finder among them, is gone.
  ///
  /// A find bar opens with the text of the pasteboard and searches for it at once, which any
  /// other app or test run may have written; typing while that search runs would race with it.
  static func preserving(_ body: @MainActor () async throws -> Void) async rethrows {
    let restore = save()
    defer { restore() }
    NSPasteboard(name: .find).clearContents()
    try await body()
  }

  /// Saves what the find pasteboard holds and returns what puts it back.
  private static func save() -> () -> Void {
    let pasteboard = NSPasteboard(name: .find)
    let items = (pasteboard.pasteboardItems ?? []).map { item in
      item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
    return {
      pasteboard.clearContents()
      let restored = items.map { pairs in
        let item = NSPasteboardItem()
        for (type, data) in pairs {
          item.setData(data, forType: type)
        }
        return item
      }
      if !restored.isEmpty {
        pasteboard.writeObjects(restored)
      }
    }
  }
}
