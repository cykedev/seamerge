import FolderCompare
import Testing

@testable import SeamergeUI

/// How the list of a collection shows what happened to a file.
struct CollectedFilePresentationTests {
  @Test func fileThatCannotBeReadSaysSoAndWhyInItsHelpTag() {
    let reason = "You don’t have permission to read it."
    let presentation = CollectedFile.Change.unreadable(reason: reason).presentation

    #expect(presentation.word == "Can’t Read")
    #expect(presentation.toolTip(for: "Logs") == "Logs (Can’t Read: \(reason))")
  }
}
