public import Foundation
import MergeModel
import os

/// The folder that keeps the copies of the patches that windows show.
///
/// Each copy lies in a folder of its own, as `<id>/<file>/a/<name>` and `<id>/<file>/b/<name>`
/// for the two sides of each file of the patch, in UTF-8. A copy goes with the window that shows
/// it; those that a crash left behind go the next time the app starts.
public struct PatchCache: Sendable {
  /// The folder that holds a folder for each copy.
  public let folder: URL

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Creates a cache in `folder`.
  public init(folder: URL) {
    self.folder = folder
  }

  /// The cache of the user: `Seamerge/Patch` in the caches folder.
  public static var standard: PatchCache {
    let caches =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return PatchCache(folder: caches.appending(path: "Seamerge/Patch"))
  }

  /// Reads `text` as a unified diff and keeps the two sides of each of its files, away from the
  /// main actor.
  ///
  /// - Parameter fileName: The name of the file the patch was read from, or `nil` for a patch
  ///   from standard input.
  /// - Throws: ``SessionLoadingError/unreadablePatch`` if `text` is not a unified diff of two
  ///   sides, ``SessionLoadingError/comparisonFailed`` if the copy cannot be written.
  @concurrent
  public func keep(_ text: Data, fileName: String?) async throws(SessionLoadingError)
    -> PatchCopy
  {
    let files: [PatchFile]
    do {
      files = try PatchFile.files(in: text)
    } catch {
      throw .unreadablePatch
    }
    let copyFolder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)
      let kept = try files.enumerated().map { index, file in
        let fileFolder = copyFolder.appending(path: String(index + 1), directoryHint: .isDirectory)
        return PatchCopy.File(
          old: try Self.keep(file.old, path: file.oldPath, in: fileFolder.appending(path: "a")),
          new: try Self.keep(file.new, path: file.newPath, in: fileFolder.appending(path: "b")),
          path: file.newPath ?? file.oldPath ?? "")
      }
      return PatchCopy(folder: copyFolder, fileName: fileName, files: kept)
    } catch {
      Self.logger.error("Cannot keep a patch: \(error, privacy: .public)")
      PatchCopy(folder: copyFolder, fileName: fileName, files: []).remove()
      throw .comparisonFailed
    }
  }

  /// Writes `side`, the side of a file of a patch whose path is `path`, into `folder` under the
  /// last part of the path, and returns the file that holds it; `/dev/null` for a side without a
  /// path, and nothing written for a side without lines.
  private static func keep(
    _ side: PatchFile.Side, path: String?, in folder: URL
  ) throws -> SessionFile {
    guard let path else {
      // A missing side of a binary file holds nothing to say; the side with a path tells.
      return SessionFile(
        url: URL(filePath: "/dev/null"), label: "", patchSide: side.isBinary ? nil : side)
    }
    let name = (path as NSString).lastPathComponent
    let url = folder.appending(path: name.isEmpty ? "file" : name, directoryHint: .notDirectory)
    if !side.isBinary {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(side.text.utf8).write(to: url)
    }
    return SessionFile(url: url, label: path, patchSide: side)
  }

  /// Removes the copies that were made before `date`, as those of windows that a crash left
  /// behind; copies made since stay, as those of a window that opens already.
  @concurrent
  public func removeLeftovers(madeBefore date: Date) async {
    for error in FileManager.default.removeItems(in: folder, madeBefore: date) {
      Self.logger.error("Cannot remove a leftover copy of a patch: \(error, privacy: .public)")
    }
  }
}
