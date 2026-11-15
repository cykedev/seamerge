import Foundation
import SeamergeUI
import Testing

/// How the service Compare with Seamerge sorts out a selection of the Finder, row by row of what
/// it promises.
@MainActor
struct ServiceSelectionTests {
  @Test func oneFileOrOneFolderIsComparedWithWhatComesNext() throws {
    let sandbox = try AppSandbox()
    let file = try sandbox.file("a.txt")
    let folders = try sandbox.folders()

    #expect(ServiceSelection([file]) == .one(file))
    #expect(ServiceSelection([plainURL(of: folders.left)]) == .one(folders.left))
  }

  @Test func twoFilesAreComparedAtOnceWithTheOlderOnTheLeft() throws {
    let sandbox = try AppSandbox()
    let older = try sandbox.file("older.txt")
    let newer = try sandbox.file("newer.txt")
    try setModified(older, to: Date(timeIntervalSince1970: 1_000_000))
    try setModified(newer, to: Date(timeIntervalSince1970: 2_000_000))
    let comparison = ServiceSelection.comparison(FileComparison(left: older, right: newer))

    #expect(ServiceSelection([newer, older]) == comparison)
    #expect(ServiceSelection([older, newer]) == comparison)
  }

  @Test func twoFilesOfTheSameAgeOrOfNoKnownAgeKeepTheOrderOfTheFinder() throws {
    let sandbox = try AppSandbox()
    let first = try sandbox.file("first.txt")
    let second = try sandbox.file("second.txt")
    let date = Date(timeIntervalSince1970: 1_000_000)
    try setModified(first, to: date)
    try setModified(second, to: date)
    let gone = sandbox.folder.appending(path: "gone.txt")

    #expect(
      ServiceSelection([second, first])
        == .comparison(FileComparison(left: second, right: first)))
    #expect(
      ServiceSelection([first, gone]) == .comparison(FileComparison(left: first, right: gone)))
  }

  @Test func twoFoldersAreComparedAtOnce() throws {
    let sandbox = try AppSandbox()
    let folders = try sandbox.folders()

    #expect(
      ServiceSelection([plainURL(of: folders.left), plainURL(of: folders.right)])
        == .comparison(FileComparison(folders: folders)))
  }

  @Test func threeFilesGoIntoTheFieldsInTheOrderOfTheFinder() throws {
    let sandbox = try AppSandbox()
    let files = [try sandbox.file("b.txt"), try sandbox.file("a.txt"), try sandbox.file("o.txt")]

    #expect(ServiceSelection(files) == .threeFiles(files))
  }

  @Test func moreThanThreeOrFilesWithFoldersOrNothingAreNotCompared() throws {
    let sandbox = try AppSandbox()
    let files = try (1...4).map { try sandbox.file("\($0).txt") }
    let folder = plainURL(of: try sandbox.folders().left)

    for urls in [
      files, [files[0], folder], [files[0], files[1], folder], [folder, folder, folder], [],
    ] {
      #expect(ServiceSelection(urls) == .unsupported, "\(urls.map(\.lastPathComponent))")
    }
  }

  /// `url` without the slash that marks it as a folder, as a pasteboard may give it.
  private func plainURL(of url: URL) -> URL {
    URL(filePath: url.path(percentEncoded: false), directoryHint: .notDirectory)
  }

  private func setModified(_ url: URL, to date: Date) throws {
    try FileManager.default.setAttributes(
      [.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
  }
}
