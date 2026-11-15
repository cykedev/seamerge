import AppKit

/// The find pasteboard of the system, which the finder of a find bar writes its search text to.
@MainActor
enum FindPasteboard {
  /// Runs `body` and then puts back what the find pasteboard held before, also if `body` fails,
  /// once what `body` made, its finder among them, is gone.
  static func preserving(_ body: @MainActor () async throws -> Void) async rethrows {
    let restore = save()
    defer { restore() }
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
