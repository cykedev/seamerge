import AppKit

/// What the clipboard holds that a field of a sheet of files takes: files and folders copied in
/// the Finder, or text.
enum ClipboardContent: Equatable {
  /// Files and folders, each folder as a directory path.
  case files([URL])

  /// Text, plain or formatted, which ``text(on:)`` reads once it is pasted.
  case text

  /// What `pasteboard` holds that a field takes, or `nil` for nothing it takes, such as an image
  /// or files that are no longer there.
  ///
  /// Files come before text, since the Finder puts their names beside them as text. Text is
  /// known by its type alone, so that asking, as each check of Paste does, never reads megabytes
  /// of it; empty text counts as text until it is pasted.
  @MainActor
  static func available(on pasteboard: NSPasteboard) -> ClipboardContent? {
    let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    if pasteboard.canReadObject(forClasses: [NSURL.self], options: fileOptions) {
      return FileDrop.files(on: pasteboard).map(ClipboardContent.files)
    }
    let holdsText =
      pasteboard.availableType(from: [.string]) != nil
      || pasteboard.canReadObject(forClasses: [NSAttributedString.self])
    return holdsText ? .text : nil
  }

  /// The text on `pasteboard` without its formatting, or `nil` if it holds none or only empty
  /// text.
  @MainActor
  static func text(on pasteboard: NSPasteboard) -> String? {
    let text =
      pasteboard.string(forType: .string)
      ?? (pasteboard.readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString])?
      .first?.string
    return text?.isEmpty == false ? text : nil
  }
}
