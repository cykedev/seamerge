import Foundation
import SeamergeCLI
import Synchronization
import Testing

/// Stands in for the `seamerge` executable when Git runs it.
///
/// The package builds no executable; the app's project does. So Git runs a shell script that hands
/// its arguments, working directory and environment to the test through a named pipe. The test
/// runs ``SeamergeCommand`` with them in its own process and sends back the exit status and the
/// error output through a second pipe, and the script passes them on to Git.
///
/// Neither side blocks the other for good: the test holds the request pipe open for reading and
/// writing, so the script can always write its request, and the script holds the response pipe
/// open the same way before it writes the request, so the test can always answer while the script
/// lives.
final class ToolTrampoline: Sendable {
  /// The script Git runs in place of the command.
  let executable: URL

  private let requestHandle: FileHandle
  private let responsePipe: URL
  private let invocations: AsyncStream<Invocation>
  private let invocationSink: AsyncStream<Invocation>.Continuation

  /// What Git started the command with.
  struct Invocation: Sendable {
    var processID: pid_t
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]
  }

  /// Creates the script and its pipes in `directory`.
  init(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    executable = directory.appending(path: "seamerge")
    let requestPipe = directory.appending(path: "request")
    responsePipe = directory.appending(path: "response")
    for pipe in [requestPipe, responsePipe] {
      try #require(mkfifo(pipe.path, 0o600) == 0, "mkfifo \(pipe.path): errno \(errno)")
    }
    // The environment comes first, as Git's variables end in an empty field; then the process,
    // the working directory, the number of arguments and the arguments.
    let script = """
      #!/bin/bash
      exec 4<>'\(responsePipe.path)'
      { env -0; printf '\\0'; printf '%s\\0' "$$" "$(pwd -P)" "$#" "$@"; } > '\(requestPipe.path)'
      IFS= read -r status <&4
      IFS= read -r message <&4
      [ -z "$message" ] || printf '%s\\n' "$message" >&2
      exit "$status"

      """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    let descriptor = open(requestPipe.path, O_RDWR | O_NONBLOCK)
    try #require(descriptor >= 0, "open \(requestPipe.path): errno \(errno)")
    requestHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    (invocations, invocationSink) = AsyncStream.makeStream(of: Invocation.self)
    let buffer = Mutex(Data())
    requestHandle.readabilityHandler = { [invocationSink] handle in
      let data = handle.availableData
      buffer.withLock { buffer in
        buffer.append(data)
        while let invocation = Self.takeInvocation(from: &buffer) {
          invocationSink.yield(invocation)
        }
      }
    }
  }

  deinit {
    requestHandle.readabilityHandler = nil
    invocationSink.finish()
  }

  /// Waits until Git starts the command and returns what it was started with.
  ///
  /// Cancelling the task ends the wait.
  func nextInvocation() async throws -> Invocation {
    var iterator = invocations.makeAsyncIterator()
    guard let invocation = await iterator.next() else { throw CancellationError() }
    return invocation
  }

  /// Runs the command for the next invocation of Git and lets the script end with its result.
  @discardableResult
  func runNextInvocation(of command: SeamergeCommand) async throws -> CommandResult {
    let invocation = try await nextInvocation()
    let result = await command.run(
      invocation.arguments, workingDirectory: invocation.workingDirectory,
      environment: invocation.environment)
    try finish(with: result)
    return result
  }

  /// Lets the waiting script end with the exit status and error output of `result`.
  ///
  /// - Throws: An error if no script waits for an answer.
  func finish(with result: CommandResult) throws {
    let descriptor = open(responsePipe.path, O_WRONLY | O_NONBLOCK)
    try #require(descriptor >= 0, "No script waits for an answer: errno \(errno)")
    defer { close(descriptor) }
    _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
    let message = result.errorOutput.split(separator: "\n").first ?? ""
    let response = Array("\(result.exitStatus)\n\(message)\n".utf8)
    let written = response.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    try #require(written == response.count, "write: errno \(errno)")
  }

  /// Whether a script waits for an answer.
  var hasWaitingScript: Bool {
    let descriptor = open(responsePipe.path, O_WRONLY | O_NONBLOCK)
    guard descriptor >= 0 else { return false }
    close(descriptor)
    return true
  }

  /// Removes the first complete request from `buffer` and returns it, or returns `nil` if the
  /// buffer holds no complete request yet.
  private static func takeInvocation(from buffer: inout Data) -> Invocation? {
    var fields: [String] = []
    var fieldStart = buffer.startIndex
    var environmentEnd: Int?
    for index in buffer.indices where buffer[index] == 0 {
      fields.append(String(decoding: buffer[fieldStart..<index], as: UTF8.self))
      fieldStart = index + 1
      if environmentEnd == nil, fields.last == "" {
        environmentEnd = fields.count - 1
      }
      guard let environmentEnd, fields.count >= environmentEnd + 4,
        let count = Int(fields[environmentEnd + 3]), fields.count == environmentEnd + 4 + count,
        let processID = pid_t(fields[environmentEnd + 1])
      else { continue }
      var environment: [String: String] = [:]
      for entry in fields[..<environmentEnd] {
        let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        environment[String(parts[0])] = parts.count == 2 ? String(parts[1]) : ""
      }
      buffer.removeSubrange(buffer.startIndex..<fieldStart)
      return Invocation(
        processID: processID,
        arguments: Array(fields[(environmentEnd + 4)...]),
        workingDirectory: URL(
          filePath: fields[environmentEnd + 2], directoryHint: .isDirectory),
        environment: environment)
    }
    return nil
  }
}
