import Foundation
import Testing

@testable import Integration

/// What the seamerge command offers the user: the commands to type and the prompt of the dialog.
struct CommandLineToolStatusTests {
  @Test func typedCommandQuotesOnlyWhatNeedsIt() {
    let status = CommandLineToolStatus(
      entry: .none, link: URL(filePath: "/usr/local/bin/seamerge"),
      helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
      hasLinkFolder: true, problem: nil)

    #expect(
      CommandLineToolChange.typedCommands(for: status) == [
        "sudo ln -sf /Applications/Seamerge.app/Contents/Helpers/seamerge /usr/local/bin/seamerge"
      ])
    #expect(CommandLineToolChange.shellQuoted("/Apps/Ada's Tools") == #"'/Apps/Ada'\''s Tools'"#)
  }

  @Test func dialogNamesSeamergeAndWhatItDoes() {
    func prompt(_ entry: CommandLineToolStatus.Entry) -> String {
      CommandLineToolStatus(
        entry: entry, link: URL(filePath: "/usr/local/bin/seamerge"),
        helper: URL(filePath: "/Applications/Seamerge.app/Contents/Helpers/seamerge"),
        hasLinkFolder: true, problem: nil
      ).dialogPrompt
    }

    #expect(prompt(.none) == "Seamerge wants to install the seamerge command in /usr/local/bin.")
    #expect(
      prompt(.otherCopy(app: "/Volumes/Seamerge/Seamerge.app"))
        == "Seamerge wants to update the seamerge command in /usr/local/bin.")
    #expect(
      prompt(.thisCopy) == "Seamerge wants to remove the seamerge command from /usr/local/bin.")
  }
}
