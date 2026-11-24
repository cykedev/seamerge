public import Foundation
import os

/// Text pasted from the clipboard into a field of the sheet Compare Files, kept as a file so
/// that it is compared as one.
///
/// The text is fixed as it was pasted: later changes of the clipboard do not reach it. Its copy
/// lies in a folder of its own, which goes with the window that compares it, or with the sheet
/// if no window took it. Such a side is called Clipboard; it is never written, and no list of
/// recent comparisons keeps it.
public struct PastedText: Sendable, Hashable {
  /// The file that holds the text, in UTF-8.
  let url: URL

  /// How many lines the text has; a last line without a line break counts.
  let lineCount: Int

  /// When the text was pasted.
  let date: Date

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The name of a side that holds pasted text.
  static var name: String {
    String(
      localized: "Clipboard", bundle: .module,
      comment: "The name of a side that holds text pasted from the clipboard.")
  }

  /// The name of the side in a header, a title and for VoiceOver: Clipboard, with the time it was
  /// pasted if `withTime`, which tells two such sides apart.
  func name(withTime: Bool) -> String {
    guard withTime else { return Self.name }
    return String(
      localized: "Clipboard \(time)", bundle: .module,
      comment:
        "The name of a side with text pasted from the clipboard while the other side holds such text as well, with the time it was pasted, such as Clipboard 14:32."
    )
  }

  /// What a field says below the name: the number of lines and the time it was pasted.
  var details: String {
    String(
      localized: "\(lineCount) lines · \(time)", bundle: .module,
      comment: "Compare Files: below Clipboard in a field, such as 12 lines · 14:32.")
  }

  /// What VoiceOver says for a field that holds the text.
  var spokenValue: String {
    String(
      localized: "Clipboard, \(lineCount) lines", bundle: .module,
      comment:
        "VoiceOver: a field with text pasted from the clipboard, such as Clipboard, 12 lines.")
  }

  private var time: String {
    date.formatted(date: .omitted, time: .shortened)
  }

  /// Removes the copy of the text with its folder.
  func remove() {
    let folder = url.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      Self.logger.error("Cannot remove pasted text: \(error, privacy: .public)")
    }
  }
}
