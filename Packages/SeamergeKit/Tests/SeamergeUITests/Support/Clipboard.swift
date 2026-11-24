import AppKit
import Testing

@testable import SeamergeUI

/// A clipboard of its own for a test, and a cache of its own for the text pasted from it, which
/// it removes once the test lets go of it.
@MainActor
final class Clipboard {
  let pasteboard = NSPasteboard.withUniqueName()
  let cache: PastedTextCache

  init() {
    cache = PastedTextCache(
      folder: FileManager.default.temporaryDirectory.appending(
        path: "Clipboard-\(UUID().uuidString)", directoryHint: .isDirectory))
  }

  isolated deinit {
    pasteboard.releaseGlobally()
    guard FileManager.default.fileExists(atPath: cache.folder.path(percentEncoded: false)) else {
      return
    }
    do {
      try FileManager.default.removeItem(at: cache.folder)
    } catch {
      Issue.record(error, "The pasted text could not be removed")
    }
  }

  /// Puts `text` on the clipboard as plain text.
  func copy(_ text: String) {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// Puts `files` on the clipboard, as the Finder does when they are copied: with their names as
  /// text beside them.
  func copy(files: [URL]) {
    pasteboard.clearContents()
    pasteboard.writeObjects(files.map { $0 as NSURL })
    pasteboard.setString(
      files.map(\.lastPathComponent).joined(separator: "\r"), forType: .string)
  }

  /// The copies of pasted text in the cache, each in a folder of its own.
  var copies: [URL] {
    get throws {
      let folder = cache.folder
      guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
        return []
      }
      return try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    }
  }
}
