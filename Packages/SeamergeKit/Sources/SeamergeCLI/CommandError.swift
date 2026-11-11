import Foundation
import SessionIPC

/// Why the command ends without a session outcome.
///
/// Each case becomes one line on standard error, which says what went wrong and what to do next,
/// and an exit status.
enum CommandError: Error {
  /// An argument starts with a dash but names no option of the merge.
  case unknownOption(String)

  /// An argument starts with a dash but names no option of the comparison; it may be a file.
  case unknownOptionOrFile(String)

  /// The option is the last argument, without its value.
  case missingValue(option: String)

  /// The option is given more than once.
  case repeatedOption(String)

  /// The merge lacks an option it needs.
  case missingOption(String)

  /// The argument is left over after all files are named.
  case unexpectedArgument(String)

  /// The comparison lacks this many of its two files.
  case missingFiles(count: Int)

  /// A file is named by an empty argument; the associated value is its option, if it has one.
  case emptyFileName(option: String?)

  /// Nothing exists at the path.
  case fileNotFound(path: String)

  /// The path names a folder where a file is needed.
  case folderInsteadOfFile(path: String)

  /// The file exists but the command may not read it.
  case fileNotReadable(path: String)

  /// The folder the result is to be saved in does not exist.
  case outputFolderNotFound(path: String)

  /// The app could not be started; the associated value is the reason the system gives.
  case appNotOpened(reason: String)

  /// No app answered on the socket in time.
  case appNotAnswering

  /// The app answered but does not understand the request, so it is another version.
  case appRefusedRequest

  /// The socket could not be used; the associated value says why.
  case connectionNotPossible(reason: String)

  /// The connection ended before the window was closed.
  case connectionLost

  /// The status the command ends with.
  var exitStatus: Int32 {
    switch self {
    case .connectionLost:
      1
    case .unknownOption, .unknownOptionOrFile, .missingValue, .repeatedOption, .missingOption,
      .unexpectedArgument, .missingFiles, .emptyFileName, .fileNotFound, .folderInsteadOfFile,
      .fileNotReadable, .outputFolderNotFound:
      2
    case .appNotOpened, .appNotAnswering, .appRefusedRequest, .connectionNotPossible:
      3
    }
  }

  /// The line for standard error, without the name of the command.
  var message: String {
    let seeHelp = "See 'seamerge --help'."
    return switch self {
    case .unknownOption(let option): "Unknown option '\(option)'. \(seeHelp)"
    case .unknownOptionOrFile(let argument):
      "Unknown option '\(argument)'. Put '--' before a file whose name starts with '-', "
        + "or see 'seamerge --help'."
    case .missingValue(let option): "Add a value after \(option). \(seeHelp)"
    case .repeatedOption(let option): "Give \(option) only once."
    case .missingOption(let option): "Add \(option) <file> to the merge. \(seeHelp)"
    case .unexpectedArgument(let argument): "Unexpected argument '\(argument)'. \(seeHelp)"
    case .missingFiles(count: 1): "Name a second file to compare. \(seeHelp)"
    case .missingFiles: "Name two files to compare. \(seeHelp)"
    case .emptyFileName(let option?): "The file name after \(option) is empty. Name a file."
    case .emptyFileName(nil): "A file name is empty. Name a file."
    case .fileNotFound(let path): "Cannot find '\(path)'. Check the path."
    case .folderInsteadOfFile(let path): "'\(path)' is a folder. Name a file instead."
    case .fileNotReadable(let path): "Cannot read '\(path)'. Check its permissions."
    case .outputFolderNotFound(let path):
      "Cannot find the folder to save '\(path)' in. Check the path."
    case .appNotOpened(let reason):
      "Cannot open Seamerge (\(reason.trimmingTrailingPeriod)). "
        + "Open it once from the Finder, then try again."
    case .appNotAnswering: "Seamerge does not answer. Quit Seamerge, then try again."
    case .appRefusedRequest:
      "Seamerge cannot read the request; it may be another version. Quit Seamerge, then try again."
    case .connectionNotPossible(let reason):
      "Cannot connect to Seamerge (\(reason)). Quit Seamerge, then try again."
    case .connectionLost:
      "Lost the connection to Seamerge before the window was closed. Run the command again."
    }
  }

  /// The error a failed session ends the command with.
  init(_ error: SessionError) {
    switch error {
    case .serverUnreachable:
      self = .appNotAnswering
    case .rejected, .unsupportedVersion:
      self = .appRefusedRequest
    case .disconnected, .cancelled, .malformedMessage, .messageTooLong:
      self = .connectionLost
    case .socketPathTooLong(let path):
      self = .connectionNotPossible(reason: "the socket path \(path) is too long")
    case .socketCallFailed(let call, let code):
      self = .connectionNotPossible(reason: "\(call): \(String(cString: strerror(code)))")
    case .socketDirectoryUnavailable(let path, let reason):
      self = .connectionNotPossible(reason: "\(path): \(reason)")
    case .socketInUse(let path), .socketPathOccupied(let path):
      self = .connectionNotPossible(reason: "\(path) is in use")
    }
  }
}

extension String {
  /// The text without the period that ends a sentence, so that it fits into parentheses.
  fileprivate var trimmingTrailingPeriod: String {
    hasSuffix(".") ? String(dropLast()) : self
  }
}
