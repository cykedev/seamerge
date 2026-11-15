import Foundation
import Testing

@testable import SeamergeUI

/// Two folders on disk for the tests of comparisons of folders, in a temporary folder of their
/// own that goes with the value.
struct SampleFolders: ~Copyable {
  /// The folder that holds both.
  let folder: URL

  /// The folder on the left.
  let left: URL

  /// The folder on the right.
  let right: URL

  /// Makes two empty folders named `leftName` and `rightName`.
  init(left leftName: String = "Orders 1.0", right rightName: String = "Orders 1.1") throws {
    folder = FileManager.default.temporaryDirectory.appending(
      path: "SampleFolders-\(UUID().uuidString)", directoryHint: .isDirectory)
    left = folder.appending(path: leftName, directoryHint: .isDirectory)
    right = folder.appending(path: rightName, directoryHint: .isDirectory)
    for url in [left, right] {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  deinit {
    do {
      // Folders a test made unreadable cannot be removed until they are readable again.
      if let enumerator = FileManager.default.enumerator(atPath: folder.path) {
        for case let path as String in enumerator
        where enumerator.fileAttributes?[.type] as? FileAttributeType != .typeSymbolicLink {
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: path).path)
        }
      }
      try FileManager.default.removeItem(at: folder)
    } catch {
      Issue.record(error, "The sample folders could not be removed")
    }
  }

  /// The pair of the two folders.
  var pair: FolderPair {
    FolderPair(left: left, right: right)
  }

  /// Writes `text` to the file at `path` in the left folder, if `text` is not `nil`, and
  /// `rightText` to the same path in the right folder.
  func write(_ path: String, left text: String?, right rightText: String?) throws {
    if let text {
      try write(text, to: left.appending(path: path))
    }
    if let rightText {
      try write(rightText, to: right.appending(path: path))
    }
  }

  /// Writes `text` to the file at `url`, with the folders it needs.
  func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  /// Fills the folders with two versions of a small project: changed, new, deleted and
  /// identical files, a file that changed but kept its size, and a deep path with a long name.
  @MainActor func fillWithProject() throws {
    try write(
      "Sources/Orders/OrderService.swift", left: SampleCollections.orderOld,
      right: SampleCollections.orderNew)
    try write("Sources/Orders/Discount.swift", left: nil, right: SampleCollections.discount)
    try write("Sources/Orders/Order.swift", left: Self.order, right: Self.order)
    try write("Sources/Orders/Receipt.swift", left: Self.receipt, right: Self.receipt)
    try write(
      "README.md", left: SampleCollections.readmeOld, right: SampleCollections.readmeNew)
    try write("prices.txt", left: "apple 1.20\npear 0.90\n", right: nil)
    try write("VERSION", left: "1.0\n", right: "1.1\n")
    try write("LICENSE", left: "MIT License\n", right: "MIT License\n")
    try write(
      "Resources/Configuration/Environments/Production/prices-and-discounts-for-every-region.json",
      left: "{\n  \"retries\": 3\n}\n", right: "{\n  \"retries\": 5\n}\n")
    try write(".DS_Store", left: "left", right: "right side")
    try write(".git/HEAD", left: "ref: refs/heads/main\n", right: "ref: refs/heads/next\n")
  }

  static let order = "struct Order {\n  var items: [String]\n}\n"
  static let receipt = "struct Receipt {\n  var total: Double\n}\n"
}

extension FileCollection {
  /// A collection that compares `folders` and gathers changes on disk quickly, compared once.
  @MainActor
  static func compared(_ folders: borrowing SampleFolders) async -> FileCollection {
    let collection = FileCollection(
      comparer: FolderComparer(
        folders: folders.pair, linkFolder: folders.folder.appending(path: "links")),
      latency: .milliseconds(50))
    collection.startComparing()
    await collection.waitUntilCompared()
    return collection
  }
}
