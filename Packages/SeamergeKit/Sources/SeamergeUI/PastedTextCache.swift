public import Foundation
import os

/// The folder that keeps the copies of text pasted from the clipboard while a sheet or a window
/// shows them.
///
/// Each copy lies in a folder of its own. A copy goes with the window that compares it, or with
/// the sheet if no window took it; those that a crash left behind go the next time the app
/// starts.
public struct PastedTextCache: Sendable {
  /// The folder that holds a folder for each copy.
  public let folder: URL

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// The name of the file of each copy.
  private static let fileName = "Clipboard.txt"

  /// Creates a cache in `folder`.
  public init(folder: URL) {
    self.folder = folder
  }

  /// The cache of the user: `Seamerge/Clipboard` in the caches folder.
  public static var standard: PastedTextCache {
    let caches =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return PastedTextCache(folder: caches.appending(path: "Seamerge/Clipboard"))
  }

  /// Keeps `text`, pasted at `date`, in UTF-8 with its line breaks as they are, in a folder of
  /// its own.
  ///
  /// - Throws: ``PastedTextError/cannotKeep`` if the copy cannot be written.
  func keep(_ text: String, pastedAt date: Date) throws(PastedTextError) -> PastedText {
    let copyFolder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let url = copyFolder.appending(path: Self.fileName)
    let bytes = Data(text.utf8)
    do {
      try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)
      try bytes.write(to: url)
    } catch {
      Self.logger.error("Cannot keep pasted text: \(error, privacy: .public)")
      throw .cannotKeep
    }
    return PastedText(url: url, lineCount: Self.lineCount(of: bytes), date: date)
  }

  /// The number of lines of the text in `bytes`, as the panes count them: each LF, CR LF and lone
  /// CR ends one, and a last line without a line break counts as well.
  static func lineCount(of bytes: Data) -> Int {
    let (lf, cr): (UInt8, UInt8) = (0x0A, 0x0D)
    var count = 0
    var previous: UInt8?
    for byte in bytes {
      if byte == lf, previous != cr {
        count += 1
      } else if byte == cr {
        count += 1
      }
      previous = byte
    }
    if let previous, previous != lf, previous != cr {
      count += 1
    }
    return count
  }

  /// Removes the copies that were made before `date`, as those of windows that a crash left
  /// behind; copies made since stay, as those of a sheet that is open already.
  @concurrent
  public func removeLeftovers(madeBefore date: Date) async {
    for error in FileManager.default.removeItems(in: folder, madeBefore: date) {
      Self.logger.error("Cannot remove a leftover copy: \(error, privacy: .public)")
    }
  }
}
