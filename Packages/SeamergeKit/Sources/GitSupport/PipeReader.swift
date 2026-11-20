package import Dispatch
package import Foundation
import Synchronization

/// Collects everything a process writes into a pipe.
package final class PipeReader: Sendable {
  /// The pipe to hand to the process.
  package let pipe = Pipe()
  private let collected = Mutex(Data())

  /// Creates a reader with a pipe of its own.
  package init() {}

  /// What has been read so far; everything once the group of ``readToEnd(in:)`` has finished.
  package var data: Data { collected.withLock { $0 } }

  /// Reads the pipe to its end in the background, as a member of `group`.
  ///
  /// Reading as data arrives keeps the pipe from filling up, which would block the process, and
  /// occupies no thread while the process is silent.
  package func readToEnd(in group: DispatchGroup) {
    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      if chunk.isEmpty {
        handle.readabilityHandler = nil
        group.leave()
      } else {
        self.collected.withLock { $0.append(chunk) }
      }
    }
  }
}
