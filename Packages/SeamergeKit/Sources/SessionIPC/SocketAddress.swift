import Darwin

/// The address of a Unix domain socket: the path of its file.
struct SocketAddress: Sendable {
  /// The path of the socket file.
  let path: String

  private let storage: sockaddr_un

  /// Creates the address of the socket at `path`.
  ///
  /// - Throws: ``SessionError/socketPathTooLong(path:)`` if the path, with its terminating zero,
  ///   does not fit into the address.
  init(path: String) throws(SessionError) {
    var storage = sockaddr_un()
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: storage.sun_path)
    guard bytes.count < capacity else { throw .socketPathTooLong(path: path) }
    withUnsafeMutableBytes(of: &storage.sun_path) { pathBytes in
      pathBytes.copyBytes(from: bytes)
      pathBytes[bytes.count] = 0
    }
    storage.sun_family = sa_family_t(AF_UNIX)
    storage.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    self.path = path
    self.storage = storage
  }

  /// Calls `body` with the address in the form the socket calls take.
  func withSocketAddress<Result>(
    _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result
  ) -> Result {
    withUnsafePointer(to: storage) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
        body(address, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }
}
