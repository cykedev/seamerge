public import Foundation
import GitSupport
import MergeModel
import os

/// The folder that keeps copies of the files of collections while their windows are open.
///
/// Git and Tower delete the temporary files they hand over as soon as the call ends, which for a
/// collection is long before its window closes; so the app copies every side that is not a file
/// of the working tree. The copies go with the window, and those that a crash left behind go the
/// next time the app starts.
public struct CollectionCache: Sendable {
  /// The folder that holds a folder for each collection.
  public let folder: URL

  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Creates a cache in `folder`.
  public init(folder: URL) {
    self.folder = folder
  }

  /// The cache of the user: `Seamerge/Collections` in the caches folder.
  public static var standard: CollectionCache {
    let caches =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return CollectionCache(folder: caches.appending(path: "Seamerge/Collections"))
  }

  /// A new, empty folder for the copies of one collection.
  public func makeFolder() -> URL {
    folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }

  /// `file` with each side that lies outside `workingTree` and is not missing replaced by a copy
  /// in `collectionFolder`.
  ///
  /// - Throws: ``SessionLoadingError/unreadableFile(_:)`` if a side cannot be copied.
  @concurrent
  public func keep(
    _ file: CollectedFile, in collectionFolder: URL, workingTree: URL
  ) async throws(SessionLoadingError) -> CollectedFile {
    let fileFolder = collectionFolder.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    var kept = file
    kept.old.url = try copy(
      file.old.url, to: fileFolder.appending(path: "old"), unlessIn: workingTree)
    kept.new.url = try copy(
      file.new.url, to: fileFolder.appending(path: "new"), unlessIn: workingTree)
    return kept
  }

  /// Removes the copies of one collection.
  public func remove(_ collectionFolder: URL) {
    removeItem(at: collectionFolder)
  }

  /// Removes the copies of every collection, as those of windows that a crash left behind.
  public func removeAll() {
    removeItem(at: folder)
  }

  private func copy(
    _ url: URL, to folder: URL, unlessIn workingTree: URL
  ) throws(SessionLoadingError) -> URL {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let tree = workingTree.standardizedFileURL.resolvingSymlinksInPath().path
    guard FileOrigin(url: url) != .missing, !path.hasPrefix(tree.hasSuffix("/") ? tree : tree + "/")
    else { return url }
    let copy = folder.appending(path: url.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: url, to: copy)
    } catch {
      Self.logger.error("Cannot keep a copy of \(path): \(error, privacy: .public)")
      throw .unreadableFile(url)
    }
    return copy
  }

  private func removeItem(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      Self.logger.error("Cannot remove the copies in \(url.path): \(error, privacy: .public)")
    }
  }
}
