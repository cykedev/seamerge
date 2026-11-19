public import Foundation
import os

/// What the command writes and the status it ends with.
public struct CommandResult: Sendable, Hashable {
  /// The status the process ends with.
  ///
  /// 0 if the merge was saved or the comparison was closed; 1 if the merge was not saved or the
  /// connection to the app was lost; 2 if the arguments are invalid or a file cannot be read; 3 if
  /// the app cannot be opened or does not answer.
  public var exitStatus: Int32

  /// The text for standard output, such as the help.
  public var output: String

  /// The text for standard error: a line that says what went wrong and what to do next.
  public var errorOutput: String

  /// Creates a result.
  public init(exitStatus: Int32, output: String = "", errorOutput: String = "") {
    self.exitStatus = exitStatus
    self.output = output
    self.errorOutput = errorOutput
  }

  /// Writes the output and the error output to the given files, by default to standard output and
  /// standard error.
  public func write(
    output outputFile: FileHandle = .standardOutput,
    errorOutput errorFile: FileHandle = .standardError
  ) {
    for (text, file) in [(output, outputFile), (errorOutput, errorFile)] where !text.isEmpty {
      do {
        try file.write(contentsOf: Data(text.utf8))
      } catch {
        // There is nowhere else to say it; the exit status still tells the caller.
        Logger.seamergeCLI.error("Cannot write the output: \(String(describing: error))")
      }
    }
  }
}
