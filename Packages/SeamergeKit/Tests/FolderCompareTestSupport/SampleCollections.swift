package import FolderCompare
package import Foundation
import GitSupport
import MergeModel

/// Files of collections for the tests of windows that compare several files: real files in a
/// temporary folder, as Git hands them over.
@MainActor
package enum SampleCollections {
  /// The temporary folder that holds the folders of this test process; it is removed as the
  /// process exits, since the tests hand the folders on and none of them owns one.
  nonisolated private static let root: URL = {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "SeamergeCollections-\(UUID().uuidString)", directoryHint: .isDirectory)
    atexit { try? FileManager.default.removeItem(at: SampleCollections.root) }
    return root
  }()

  /// A new, empty temporary folder.
  package static func folder() throws -> URL {
    let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// A file of a run at `path`, number `number` of `count`, whose sides hold `old` and `new`; a
  /// missing side is `/dev/null`.
  package static func file(
    _ path: String, old: String?, new: String?, number: Int? = nil, count: Int? = nil,
    in folder: URL
  ) throws -> CollectedFile {
    let side = { (text: String?, name: String) throws -> URL in
      guard let text else { return URL(filePath: "/dev/null") }
      let url = folder.appending(path: UUID().uuidString).appending(
        path: (path as NSString).lastPathComponent)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: url)
      return url
    }
    let position = number.map { FilePosition(number: $0, count: count ?? $0) }
    return CollectedFile(
      old: SessionFile(url: try side(old, "old"), label: path),
      new: SessionFile(url: try side(new, "new"), label: path),
      difftool: DifftoolContext(path: path, filePosition: position))
  }

  /// Five files of a commit: two changed, one new, one deleted, one in a deep folder with a long
  /// name.
  package static func commit(in folder: URL) throws -> [CollectedFile] {
    let count = 5
    return [
      try file(
        "Sources/Orders/OrderService.swift", old: orderOld, new: orderNew, number: 1,
        count: count, in: folder),
      try file(
        "Sources/Orders/Discount.swift", old: nil, new: discount, number: 2, count: count,
        in: folder),
      try file("README.md", old: readmeOld, new: readmeNew, number: 3, count: count, in: folder),
      try file(
        "Resources/Configuration/Environments/Production/prices-and-discounts-for-every-region.json",
        old: "{\n  \"retries\": 3\n}\n", new: "{\n  \"retries\": 5\n}\n", number: 4,
        count: count, in: folder),
      try file(
        "prices.txt", old: "apple 1.20\npear 0.90\n", new: nil, number: 5, count: count,
        in: folder),
    ]
  }

  /// `count` changed files in folders of ten, numbered as Git numbers them; they share their
  /// sides on disk.
  package static func many(_ count: Int, in folder: URL) throws -> [CollectedFile] {
    let first = try file("Sources/Module0/File0.swift", old: orderOld, new: orderNew, in: folder)
    return (0..<count).map { index in
      var copy = first
      copy.difftool = DifftoolContext(
        path: "Sources/Module\(index / 10)/File\(index).swift",
        filePosition: FilePosition(number: index + 1, count: count))
      copy.old.label = copy.difftool.path
      copy.new.label = copy.difftool.path
      return copy
    }
  }

  package static let orderOld = """
    import Foundation

    struct OrderService {
      let retries = 3

      func place(_ order: Order) throws {
        try validate(order)
        try store(order)
      }
    }

    """

  package static let orderNew = """
    import Foundation

    struct OrderService {
      let retries = 5
      let discounts: DiscountTable

      func place(_ order: Order) throws {
        try validate(order)
        let priced = discounts.apply(to: order)
        try store(priced)
      }
    }

    """

  static let discount = """
    struct DiscountTable {
      var rates: [String: Double]

      func apply(to order: Order) -> Order {
        order
      }
    }

    """

  static let readmeOld = "# Orders\n\nPlaces orders.\n"

  static let readmeNew = "# Orders\n\nPlaces orders and applies discounts.\n\nSee Discount.swift.\n"
}
