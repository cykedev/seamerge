import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

/// Reading the files of a session: in the mode of the window, and with an error that names the
/// file to blame.
struct SessionLoadingTests {
  @Test func mergeIsComparedInTheModeOfTheWindow() async throws {
    let files = try SampleFiles()
    let session = try await Session.loadMerge(
      base: SessionFile(url: try files.file("base.txt"), label: "base"),
      a: SessionFile(url: try files.file("a.txt"), label: "a"),
      b: SessionFile(url: try files.file("b.txt"), label: "b"))

    #expect(session.kind == .merge)
    #expect(session.options.mode == .windowDefault)
  }

  @Test func fileThatIsNotTextIsNamed() async throws {
    let files = try SampleFiles()
    let image = files.folder.appending(path: "image.png")
    try Data([0, 1, 2, 0, 80, 78, 71]).write(to: image)

    await #expect(throws: SessionLoadingError.binaryFile(image)) {
      try await Session.loadMerge(
        base: nil, a: SessionFile(url: try files.file("a.txt"), label: "a"),
        b: SessionFile(url: image, label: "b"))
    }
    #expect(
      SessionLoadingError.binaryFile(image).errorDescription == "“image.png” isn’t a text file.")
  }

  @Test func fileThatCannotBeReadIsNamedWithTheNextStep() async throws {
    let files = try SampleFiles()
    let missing = files.folder.appending(path: "missing.txt")

    await #expect(throws: SessionLoadingError.unreadableFile(missing)) {
      try await Session.loadMerge(
        base: SessionFile(url: missing, label: "base"),
        a: SessionFile(url: try files.file("a.txt"), label: "a"),
        b: SessionFile(url: try files.file("b.txt"), label: "b"))
    }
    let error = SessionLoadingError.unreadableFile(missing)
    #expect(error.errorDescription == "Seamerge can’t read “missing.txt”.")
    #expect(error.recoverySuggestion?.isEmpty == false)
  }
}
