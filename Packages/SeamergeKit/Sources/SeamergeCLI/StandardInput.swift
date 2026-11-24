public import Foundation

/// The standard input of the command, from which it reads a patch.
///
/// The command reads a patch from standard input when it is told to, and, without any argument,
/// when standard input is a pipe or a file, as in `git diff | seamerge`. A terminal or
/// `/dev/null` never counts as a patch, so that the command run on its own shows its help.
public struct StandardInput: Sendable {
  /// What standard input is connected to.
  public enum Kind: Sendable, Hashable {
    /// A pipe, a socket or an ordinary file, which hands over a patch.
    case pipeOrFile

    /// A terminal, where someone would type the patch.
    case terminal

    /// `/dev/null` or another device, which hands over nothing worth reading.
    case device
  }

  /// What standard input is connected to.
  public let kind: Kind

  private let handle: FileHandle

  /// The standard input of the process.
  public static var process: StandardInput {
    StandardInput(.standardInput)
  }

  /// Standard input read from `handle`, whose kind it learns from the system.
  public init(_ handle: FileHandle) {
    self.handle = handle
    let descriptor = handle.fileDescriptor
    var status = stat()
    if isatty(descriptor) != 0 {
      kind = .terminal
    } else if fstat(descriptor, &status) == 0,
      [S_IFIFO, S_IFREG, S_IFSOCK].contains(status.st_mode & S_IFMT)
    {
      kind = .pipeOrFile
    } else {
      kind = .device
    }
  }

  /// Reads standard input to its end, or until it holds more than `limit` bytes.
  ///
  /// - Returns: The bytes read, or `nil` if there are more than `limit`.
  /// - Throws: The error of the system if standard input cannot be read.
  func readAll(atMost limit: Int) throws -> Data? {
    try handle.readToEnd(atMost: limit)
  }
}

extension FileHandle {
  /// Reads to the end of the file, or until it holds more than `limit` bytes.
  ///
  /// - Returns: The bytes read, or `nil` if there are more than `limit`.
  /// - Throws: The error of the system if the file cannot be read.
  func readToEnd(atMost limit: Int) throws -> Data? {
    var bytes = Data()
    while let chunk = try read(upToCount: 1 << 20), !chunk.isEmpty {
      bytes.append(chunk)
      guard bytes.count <= limit else { return nil }
    }
    return bytes
  }
}
