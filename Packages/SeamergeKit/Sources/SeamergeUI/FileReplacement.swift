import Foundation
import os

/// Replaces the content of a file atomically: readers see either the old or the new content,
/// and a failure leaves the file as it was.
///
/// A symbolic link is followed, so that the file it leads to is replaced and the link stays, as
/// the links of `git difftool --dir-diff` must. An existing file keeps its permissions; the
/// file system keeps its other metadata, such as Finder tags, as it swaps the files.
enum FileReplacement {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")

  /// Replaces the file at `url`, or the file a link there leads to, with `bytes`.
  ///
  /// - Throws: The error of the file system if the file cannot be written.
  static func replace(_ url: URL, with bytes: Data) throws {
    try replace(url) { try bytes.write(to: $0) }
  }

  /// Replaces the file at `url`, or the file a link there leads to, with the file that `write`
  /// writes at the location it is given, beside the file on the same volume.
  ///
  /// - Throws: The error of `write`, or of the file system if the file cannot be replaced.
  static func replace(_ url: URL, writing write: (URL) throws -> Void) throws {
    let fileManager = FileManager.default
    let destination = url.resolvingSymlinksInPath()
    let scratch = try fileManager.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination,
      create: true)
    defer { removeScratch(scratch) }
    let replacement = scratch.appending(path: destination.lastPathComponent)
    try write(replacement)
    let path = destination.path(percentEncoded: false)
    guard fileManager.fileExists(atPath: path) else {
      try fileManager.moveItem(at: replacement, to: destination)
      return
    }
    // A copied file brings the permissions of its source, which the file it replaces keeps.
    if let permissions = try fileManager.attributesOfItem(atPath: path)[.posixPermissions] {
      try fileManager.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: replacement.path(percentEncoded: false))
    }
    _ = try fileManager.replaceItemAt(destination, withItemAt: replacement)
  }

  private static func removeScratch(_ scratch: URL) {
    do {
      try FileManager.default.removeItem(at: scratch)
    } catch {
      logger.error(
        "Could not remove \(scratch.path, privacy: .public): \(error, privacy: .public)")
    }
  }
}
