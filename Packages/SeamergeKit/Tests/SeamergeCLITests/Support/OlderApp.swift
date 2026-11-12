import Darwin
import Foundation
import Testing

/// An app of an older version of the protocol in the test: it reads the request and answers with
/// one line written by hand, as a version 1 app would, then hangs up.
final class OlderApp: Sendable {
  private let descriptor: Int32
  private let task: Task<Void, Never>

  /// Listens at `url` and answers the first request with `answer`, a line of JSON without its
  /// line feed.
  init(at url: URL, answering answer: String) throws {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = Array(url.path(percentEncoded: false).utf8CString)
    try #require(path.count <= MemoryLayout.size(ofValue: address.sun_path))
    withUnsafeMutableBytes(of: &address.sun_path) { bytes in
      bytes.copyBytes(from: path.map { UInt8(bitPattern: $0) })
    }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    try #require(bound == 0 && listen(descriptor, 1) == 0)
    self.descriptor = descriptor
    task = Task.detached {
      let connection = accept(descriptor, nil, nil)
      guard connection >= 0 else { return }
      defer { close(connection) }
      var byte: UInt8 = 0
      while read(connection, &byte, 1) == 1, byte != UInt8(ascii: "\n") {}
      let line = Array((answer + "\n").utf8)
      _ = line.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
    }
  }

  /// Waits until the app has answered, then stops listening.
  func stop() async {
    await task.value
    close(descriptor)
  }
}
