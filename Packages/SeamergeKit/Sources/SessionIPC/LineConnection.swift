import Dispatch
import Foundation
import os

/// A connected socket that carries messages as lines.
///
/// Reading and writing never block a thread: a Dispatch channel waits for the socket. The channel
/// owns the descriptor until its cleanup has run, which happens once the connection is closed and
/// every pending read and write has ended.
final class LineConnection: Sendable {
  private let channel: DispatchIO
  private let queue: DispatchQueue
  private let incoming: AsyncStream<Data>

  /// Starts reading from a connected socket.
  ///
  /// The connection holds the descriptor until it is closed; nothing else may read from it or
  /// write to it.
  init(descriptor: SocketDescriptor) {
    let queue = DispatchQueue(label: "app.eiden.seamerge.session-connection")
    let channel = DispatchIO(
      type: .stream, fileDescriptor: descriptor.rawValue, queue: queue,
      cleanupHandler: { _ in withExtendedLifetime(descriptor) {} })
    channel.setLimit(lowWater: 1)
    let (incoming, continuation) = AsyncStream.makeStream(of: Data.self)
    channel.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
      if let data, !data.isEmpty { continuation.yield(Data(data)) }
      guard done else { return }
      if error != 0 && error != ECANCELED {
        Logger.sessionIPC.error("Reading from a session connection failed: errno \(error)")
      }
      continuation.finish()
    }
    self.channel = channel
    self.queue = queue
    self.incoming = incoming
  }

  deinit {
    channel.close(flags: .stop)
  }

  /// Returns the reader of the lines that arrive on the connection.
  ///
  /// - Precondition: Only one reader is used per connection; the bytes it has not handed out yet
  ///   are lost to any other.
  func makeLineReader() -> LineReader {
    LineReader(chunks: incoming.makeAsyncIterator())
  }

  /// Writes bytes to the connection and returns once they are written.
  ///
  /// - Throws: ``SessionError/disconnected`` if the other side has closed the connection or the
  ///   connection was closed.
  func write(_ bytes: Data) async throws(SessionError) {
    let data = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
    let error: Int32 = await withCheckedContinuation { continuation in
      channel.write(offset: 0, data: data, queue: queue) { done, _, error in
        if done { continuation.resume(returning: error) }
      }
    }
    guard error == 0 else {
      if error != EPIPE && error != ECANCELED {
        Logger.sessionIPC.error("Writing to a session connection failed: errno \(error)")
      }
      throw .disconnected
    }
  }

  /// Closes the connection.
  ///
  /// Pending reads and writes end at once; the reader sees the end of the lines, a pending write
  /// fails. Closing again does nothing.
  func close() {
    channel.close(flags: .stop)
  }
}

/// Splits the bytes arriving on a connection into lines.
struct LineReader {
  /// The longest line a reader accepts, line feed excluded.
  static let maximumLineLength = 1 << 20

  private var chunks: AsyncStream<Data>.Iterator
  private var buffer = Data()

  fileprivate init(chunks: AsyncStream<Data>.Iterator) {
    self.chunks = chunks
  }

  /// Returns the next line without its line feed, or `nil` once the connection has ended.
  ///
  /// Bytes after the last line feed are discarded when the connection ends: they are an incomplete
  /// message. The end also comes when the waiting task is cancelled.
  ///
  /// - Throws: ``SessionError/messageTooLong`` if a line grows beyond
  ///   ``maximumLineLength``.
  mutating func nextLine() async throws(SessionError) -> Data? {
    while true {
      let lineFeed = buffer.firstIndex(of: MessageCoding.lineFeed)
      let lineLength = buffer.distance(from: buffer.startIndex, to: lineFeed ?? buffer.endIndex)
      guard lineLength <= Self.maximumLineLength else { throw .messageTooLong }
      if let lineFeed {
        let line = Data(buffer[..<lineFeed])
        buffer = Data(buffer[buffer.index(after: lineFeed)...])
        return line
      }
      guard let chunk = await chunks.next() else {
        if !buffer.isEmpty {
          Logger.sessionIPC.notice("A session connection ended in the middle of a message")
        }
        return nil
      }
      buffer.append(chunk)
    }
  }
}
