import Foundation
import os

/// Turns the paths on the command line into absolute file URLs and checks them before the app
/// opens them.
enum FileCheck {
  /// The file `path` names, read relative to `directory` unless it is absolute.
  private static func fileURL(for path: String, in directory: URL) -> URL {
    URL(filePath: path, directoryHint: .notDirectory, relativeTo: directory).standardizedFileURL
  }

  /// The file `path` names, after checking that it can be read.
  ///
  /// - Parameter option: The option that names the file, or `nil` for a file named on its own.
  /// - Throws: ``CommandError`` if the path is empty or does not name a readable file.
  static func readableFile(
    _ path: String, option: Option?, in directory: URL
  ) throws(CommandError) -> URL {
    guard !path.isEmpty else { throw .emptyFileName(option: option?.rawValue) }
    let url = fileURL(for: path, in: directory)
    let filePath = url.path(percentEncoded: false)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) else {
      throw .fileNotFound(path: filePath)
    }
    guard !isDirectory.boolValue else { throw .folderInsteadOfFile(path: filePath) }
    guard FileManager.default.isReadableFile(atPath: filePath) else {
      throw .fileNotReadable(path: filePath)
    }
    return url
  }

  /// The common ancestor of a merge, or `nil` if there is none.
  ///
  /// A base that is left out, empty or names a file that does not exist means a merge without a
  /// common ancestor.
  ///
  /// - Throws: ``CommandError`` if the base exists but cannot be read.
  static func base(_ path: String?, in directory: URL) throws(CommandError) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    let url = fileURL(for: path, in: directory)
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
      Logger.seamergeCLI.info("The base does not exist; merging without a base")
      return nil
    }
    return try readableFile(path, option: .base, in: directory)
  }

  /// The file the result of a merge is saved to, after checking that its folder exists.
  ///
  /// The file itself need not exist; the app creates it when the merge is saved.
  ///
  /// - Throws: ``CommandError`` if the path is empty, names a folder, or its folder does not exist.
  static func outputFile(_ path: String, in directory: URL) throws(CommandError) -> URL {
    guard !path.isEmpty else { throw .emptyFileName(option: Option.output.rawValue) }
    let url = fileURL(for: path, in: directory)
    let filePath = url.path(percentEncoded: false)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
      guard !isDirectory.boolValue else { throw .folderInsteadOfFile(path: filePath) }
      return url
    }
    let folder = url.deletingLastPathComponent().path(percentEncoded: false)
    guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw .outputFolderNotFound(path: filePath) }
    return url
  }
}

extension FileCheck {
  /// The two folders `left` and `right` name, or `nil` if neither names a folder, as for a
  /// comparison of two files.
  ///
  /// - Throws: ``CommandError`` if only one of them names a folder.
  static func folders(
    _ left: String, _ right: String, in directory: URL
  ) throws(CommandError) -> (left: URL, right: URL)? {
    guard !left.isEmpty, !right.isEmpty else { return nil }
    let urls = [left, right].map { fileURL(for: $0, in: directory) }
    let isFolder = urls.map { url in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(
        atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        && isDirectory.boolValue
    }
    switch (isFolder[0], isFolder[1]) {
    case (true, true): return (urls[0], urls[1])
    case (false, false): return nil
    case (true, false): throw .folderInsteadOfFile(path: urls[0].path(percentEncoded: false))
    case (false, true): throw .folderInsteadOfFile(path: urls[1].path(percentEncoded: false))
    }
  }
}
