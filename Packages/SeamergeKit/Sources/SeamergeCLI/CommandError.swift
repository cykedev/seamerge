import Foundation
import SessionIPC
import TextIO

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

  /// Standard input could not be read; the associated value is the reason the system gives.
  case standardInputNotReadable(reason: String)

  /// The patch is larger than a request to the app holds.
  case patchTooLarge

  /// The patch is not a unified diff that the app can show; the file name is `nil` for a patch
  /// from standard input.
  case unreadablePatch(PatchReadingError, fileName: String?)

  /// The app could not read the patch that the command read.
  case patchRefused

  /// The app read the patch but could not open its window; it shows why.
  case patchWindowNotOpened

  /// The app could not be started; the associated value is the reason the system gives.
  case appNotOpened(reason: String)

  /// No app answered on the socket in time.
  case appNotAnswering

  /// The app is quitting and has not quit in time, so no copy can open the window.
  case appStillQuitting

  /// The app answered but does not understand the request, so it is another version.
  case appRefusedRequest

  /// The app understands the request but cannot open a window of its kind; the associated value
  /// tells whether the request is a comparison of two files.
  case windowNotAvailable(isComparison: Bool)

  /// The socket could not be used; the associated value says why.
  case connectionNotPossible(reason: String)

  /// The path of the socket is longer than the system allows.
  case socketPathTooLong(path: String)

  /// The folder of the socket belongs to another user or is no folder.
  case socketFolderNotPrivate(path: String)

  /// The connection ended before the window was closed.
  case connectionLost

  /// The status the command ends with.
  var exitStatus: Int32 {
    switch self {
    case .connectionLost, .windowNotAvailable:
      1
    case .unknownOption, .unknownOptionOrFile, .missingValue, .repeatedOption, .missingOption,
      .unexpectedArgument, .missingFiles, .emptyFileName, .fileNotFound, .folderInsteadOfFile,
      .fileNotReadable, .outputFolderNotFound, .standardInputNotReadable, .patchTooLarge,
      .unreadablePatch, .patchRefused:
      2
    case .appNotOpened, .appNotAnswering, .appStillQuitting, .appRefusedRequest,
      .patchWindowNotOpened,
      .connectionNotPossible,
      .socketPathTooLong, .socketFolderNotPrivate:
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
    case .standardInputNotReadable(let reason):
      "Cannot read standard input (\(reason.trimmingTrailingPeriod)). Pass the patch as a file."
    case .patchTooLarge:
      "The patch is larger than \(SessionRequest.Patch.maximumByteCount >> 20) MB. "
        + "Split it into smaller patches."
    case .unreadablePatch(let error, let fileName):
      "Cannot read \(fileName.map { "'\($0)'" } ?? "the patch"): \(error.reason)"
    case .patchRefused:
      "Seamerge cannot read the patch. Make one with 'git diff' or 'diff -u'."
    case .patchWindowNotOpened:
      "Seamerge cannot open a window for the patch; it says why. Try again."
    case .appNotOpened(let reason):
      "Cannot open Seamerge (\(reason.trimmingTrailingPeriod)). "
        + "Open it once from the Finder, then try again."
    case .appNotAnswering: "Seamerge does not answer. Quit Seamerge, then try again."
    case .appStillQuitting:
      "Seamerge is still quitting. Wait until it has quit, or force it to quit, then try again."
    case .appRefusedRequest:
      "Seamerge cannot read the request; it may be another version. Quit Seamerge, then try again."
    case .windowNotAvailable(isComparison: true):
      "This version of Seamerge cannot compare two files yet. Use another diff tool for now."
    case .windowNotAvailable(isComparison: false):
      "This version of Seamerge cannot open this merge. Use another merge tool for now."
    case .connectionNotPossible(let reason):
      "Cannot connect to Seamerge (\(reason)). Quit Seamerge, then try again."
    case .socketPathTooLong(let path):
      "Cannot connect to Seamerge: the path of its socket, '\(path)', is longer than macOS "
        + "allows. This is a bug in Seamerge; please report it."
    case .socketFolderNotPrivate(let path):
      "Cannot connect to Seamerge: '\(path)' is not a folder of yours alone. "
        + "Remove it, then open Seamerge again."
    case .connectionLost:
      "Lost the connection to Seamerge before the window was closed. Run the command again."
    }
  }

  /// The error a failed session of `request` ends the command with.
  init(_ error: SessionError, request: SessionRequest) {
    switch error {
    case .serverUnreachable:
      self = .appNotAnswering
    case .rejected(.unsupportedRequest):
      switch request {
      case .merge: self = .windowNotAvailable(isComparison: false)
      case .diff, .folders: self = .windowNotAvailable(isComparison: true)
      case .patch: self = .appRefusedRequest
      }
    case .rejected(.unreadablePatch):
      self = .patchRefused
    case .rejected(.windowNotOpened):
      self = .patchWindowNotOpened
    case .rejected, .unsupportedVersion:
      self = .appRefusedRequest
    case .disconnected, .cancelled, .malformedMessage, .messageTooLong:
      self = .connectionLost
    case .socketPathTooLong(let path):
      self = .socketPathTooLong(path: path)
    case .socketDirectoryNotPrivate(let path):
      self = .socketFolderNotPrivate(path: path)
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

extension PatchReadingError {
  /// Why the patch cannot be read and what to do, as the end of a line on standard error.
  fileprivate var reason: String {
    switch self {
    case .combinedDiff(let line):
      "line \(line) starts a combined diff of a merge, which Seamerge cannot show. "
        + "Compare with one parent instead, such as with 'git diff HEAD^1'."
    case .notUnifiedDiff:
      "it is not a unified diff. Make one with 'git diff' or 'diff -u'."
    case .malformedHunkHeader(let line):
      "line \(line) is not the header of a hunk. Check the patch."
    case .hunkWithoutFile(let line):
      "the hunk at line \(line) has no lines '---' and '+++' before it. Check the patch."
    case .truncatedHunk(let line):
      "the hunk at line \(line) ends early. Check that the patch is complete."
    case .hunkLengthMismatch(let line):
      "the hunk at line \(line) holds other lines than its header says. Check the patch."
    case .malformedFileName(let line):
      "the file name in line \(line) is not quoted as Git quotes names. Check the patch."
    }
  }
}
