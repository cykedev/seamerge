import AppKit
import FolderCompare
import GitSupport
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the pictures of the window of a patch for the visual review: one file with the bars of
/// the lines it passes over, in every look and with the other settings, and a patch of several
/// files.
@MainActor
@Suite(.serialized) struct PatchPicturesTests {
  /// A Swift file with changes near its start and further down, as a patch of Git.
  private static let patch: Data = {
    let old = (1...60).map { line in
      switch line {
      case 1: "import Foundation\n"
      case 3: "/// Greets whoever asks.\n"
      case 4: "struct Greeter {\n"
      case 5: "  var name: String\n"
      case 41: "  func greet() -> String {\n"
      case 42: "    \"Hello, \\(name)!\"\n"
      case 43: "  }\n"
      default: "\n"
      }
    }.joined()
    let greeting = "    let greeting = \"Hello\"\n    return \"\\(greeting), \\(name)!\"\n"
    let new = old.replacingOccurrences(of: "  var name: String\n", with: "  let name: String\n")
      .replacingOccurrences(of: "    \"Hello, \\(name)!\"\n", with: greeting)
    return PatchWindowTests.patch([("Sources/Greeter.swift", old, new)])
  }()

  @Test(arguments: Look.all)
  func windowOfAPatchIsPictured(look: Look) async throws {
    try await picture(
      look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "window-patch-\(look.name)")
  }

  @Test func windowOfAPatchIsPicturedWithTheOtherSettings() async throws {
    try await picture(
      look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "window-patch-without-color-light")
    try await picture(
      look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "window-patch-reduced-transparency-light")
    try await picture(
      look: .light, options: DisplayOptions(), size: nil, named: "window-patch-smallest-light")
  }

  @Test(arguments: [Look.light, .dark])
  func windowOfAPatchOfSeveralFilesIsPictured(look: Look) async throws {
    let files = try SampleFiles()
    let cache = PatchCache(folder: files.folder.appending(path: "Patch"))
    let copy = try await cache.keep(
      PatchWindowTests.patch([
        ("README.md", "# App\n\nOld text.\n", "# App\n\nNew text.\n"),
        ("Sources/New.swift", nil, "struct New {}\n"),
        ("Sources/Old.swift", "struct Old {}\n", nil),
      ]) + Self.patch, fileName: "feature.patch")
    defer { copy.remove() }
    let collection = FileCollection(
      origin: CollectionOrigin(repository: copy.folder.path(percentEncoded: false), run: nil),
      expectedCount: copy.files.count)
    for index in copy.files.indices {
      collection.add(copy.collectedFile(at: index))
    }

    try await Windows.picture(
      collection, look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "window-patch-files-\(look.name)", patch: copy)
  }

  /// Draws the window of the patch of the Swift file in `look` and `options`, at `size` or at
  /// its least size for `nil`.
  private func picture(
    look: Look, options: DisplayOptions, size: CGSize? = WindowMetrics.defaultContentSize,
    named name: String
  ) async throws {
    let files = try SampleFiles()
    let cache = PatchCache(folder: files.folder.appending(path: "Patch"))
    let copy = try await cache.keep(Self.patch, fileName: "greeter.patch")
    defer { copy.remove() }
    let file = try #require(copy.files.first)
    let session = try await Session.loadDiff(old: file.old, new: file.new, mode: .windowDefault)
    try Windows.picture(
      session,
      context: SessionContext(
        difftool: DifftoolContext(path: file.path, filePosition: FilePosition(number: 1, count: 1)),
        patch: copy),
      look: look, options: options, size: size, named: name)
  }
}
