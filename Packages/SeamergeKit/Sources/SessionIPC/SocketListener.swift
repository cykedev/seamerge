import Dispatch
import Foundation
import os

/// A socket file that accepts connections.
///
/// The listener binds the socket when it is created and accepts connections from then on. Closing
/// it, or releasing it, stops accepting, removes the socket file if it is still the one the
/// listener created, and closes the socket.
final class SocketListener: Sendable {
  /// The connections accepted so far and from now on, in the order they arrived.
  ///
  /// The sequence ends when the listener is closed. It has one reader.
  let connections: AsyncStream<SocketDescriptor>

  private let path: String
  private let socketFile: FileIdentity
  private let source: any DispatchSourceRead

  /// Binds a socket at `url` and starts accepting connections.
  ///
  /// A socket file that no server listens on any more is replaced: it is left behind by a server
  /// that ended without removing it. A missing directory for the socket is created; the directory
  /// must belong to the user, who alone may enter it.
  ///
  /// - Throws: ``SessionError/socketInUse(path:)`` if a server listens on the socket,
  ///   ``SessionError/socketPathOccupied(path:)`` if another kind of file is at `url`,
  ///   ``SessionError/socketDirectoryNotPrivate(path:)`` if its directory is not the user's, and
  ///   other ``SessionError`` cases if the socket cannot be set up.
  init(url: URL) throws(SessionError) {
    let address = try SocketAddress(path: url.path(percentEncoded: false))
    try Self.createDirectory(for: url)
    try Self.removeAbandonedSocket(at: address)
    let descriptor = try SocketDescriptor.makeUnixStream()
    try descriptor.bind(to: address)
    let socketFile: FileIdentity
    do {
      socketFile = try Self.prepareToListen(descriptor, boundTo: address)
    } catch {
      // The file was created a moment ago and never served; left behind, it would only be
      // replaced as abandoned on the next start.
      if unlink(address.path) != 0 && errno != ENOENT {
        Logger.sessionIPC.error("Removing the unused socket failed: errno \(errno)")
      }
      throw error
    }

    let (connections, continuation) = AsyncStream.makeStream(of: SocketDescriptor.self)
    let source = DispatchSource.makeReadSource(
      fileDescriptor: descriptor.rawValue,
      queue: DispatchQueue(label: "app.eiden.seamerge.session-listener"))
    source.setEventHandler {
      do {
        while let connection = try descriptor.accept() {
          continuation.yield(connection)
        }
      } catch {
        Logger.sessionIPC.error(
          "Accepting a session connection failed: \(String(describing: error))")
      }
    }
    // The handlers hold the descriptor; Dispatch releases them after the cancel handler has run,
    // which is the first moment the descriptor may be closed.
    source.setCancelHandler {
      continuation.finish()
      withExtendedLifetime(descriptor) {}
    }
    source.activate()
    self.connections = connections
    self.path = address.path
    self.socketFile = socketFile
    self.source = source
  }

  deinit {
    close()
  }

  /// Stops accepting connections and removes the socket file.
  ///
  /// The file is gone when this method returns, unless another server has replaced it, in which
  /// case it stays. The socket closes shortly afterwards. Closing again does nothing.
  func close() {
    if FileIdentity(path: path) == socketFile, unlink(path) != 0 {
      Logger.sessionIPC.error("Removing the socket at \(self.path, privacy: .public) failed")
    }
    source.cancel()
  }

  /// Restricts the socket file to the user and lets the socket listen, and returns the identity
  /// of the file.
  private static func prepareToListen(
    _ descriptor: SocketDescriptor, boundTo address: SocketAddress
  ) throws(SessionError) -> FileIdentity {
    guard let socketFile = FileIdentity(path: address.path) else {
      throw .socketCallFailed(call: "lstat", code: errno)
    }
    guard chmod(address.path, S_IRUSR | S_IWUSR) == 0 else {
      throw .socketCallFailed(call: "chmod", code: errno)
    }
    try descriptor.listen()
    return socketFile
  }

  /// Creates the directory of the socket at `url` for the user alone, or makes sure that the one
  /// there is a folder of the user, which only the user may enter.
  private static func createDirectory(for url: URL) throws(SessionError) {
    let directory = url.deletingLastPathComponent()
    // Without its final slash, so that a link in the place of the folder is not followed.
    var path = directory.path(percentEncoded: false)
    while path.count > 1 && path.hasSuffix("/") {
      path.removeLast()
    }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: S_IRWXU])
    } catch {
      throw .socketDirectoryUnavailable(path: path, reason: error.localizedDescription)
    }
    var status = stat()
    guard lstat(path, &status) == 0 else { throw .socketCallFailed(call: "lstat", code: errno) }
    guard status.st_mode & S_IFMT == S_IFDIR, status.st_uid == getuid() else {
      throw .socketDirectoryNotPrivate(path: path)
    }
    // A folder of the user that others may enter is closed to them, so that no one else can
    // reach the socket or put a file in its place.
    if status.st_mode & (S_IRWXG | S_IRWXO) != 0, chmod(path, S_IRWXU) != 0 {
      throw .socketCallFailed(call: "chmod", code: errno)
    }
  }

  /// Removes a socket file that nothing listens on any more, and leaves everything else alone.
  private static func removeAbandonedSocket(at address: SocketAddress) throws(SessionError) {
    var status = stat()
    guard lstat(address.path, &status) == 0 else {
      guard errno == ENOENT else { throw .socketCallFailed(call: "lstat", code: errno) }
      return
    }
    guard status.st_mode & S_IFMT == S_IFSOCK else {
      throw .socketPathOccupied(path: address.path)
    }
    let probe = try SocketDescriptor.makeUnixStream()
    do {
      try probe.connect(to: address)
    } catch .socketCallFailed(_, let code) where code == ENOENT {
      return
    } catch .socketCallFailed(_, let code) where code == ECONNREFUSED {
      Logger.sessionIPC.notice("Replacing an abandoned socket at \(address.path, privacy: .public)")
      guard unlink(address.path) == 0 || errno == ENOENT else {
        throw .socketCallFailed(call: "unlink", code: errno)
      }
      return
    }
    throw .socketInUse(path: address.path)
  }
}

/// What tells a file apart from another one at the same path.
private struct FileIdentity: Sendable, Equatable {
  let device: dev_t
  let inode: ino_t

  /// Reads the identity of the file at `path`, or returns `nil` if there is no file to read.
  init?(path: String) {
    var status = stat()
    guard lstat(path, &status) == 0 else { return nil }
    device = status.st_dev
    inode = status.st_ino
  }
}
