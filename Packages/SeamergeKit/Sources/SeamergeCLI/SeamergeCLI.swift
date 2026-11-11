// SeamergeCLI is the logic of the `seamerge` command: it parses the arguments,
// hands the files to the app and turns the outcome into an exit code.
import os

extension Logger {
  /// The log of the command-line tool.
  static let seamergeCLI = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeCLI")
}
