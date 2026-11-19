import Foundation
import GitSupport
import Testing

/// The exit status and the combined output of a finished `git` command.
struct GitResult {
  var status: Int32
  var output: String
}

/// Runs `git` with `arguments` in `directory` while `body` talks to it, and returns the result of
/// both once `git` has ended.
///
/// `git` runs in a process group of its own. If `body` fails or the task is cancelled, for example
/// by the time limit of a test, the whole group is killed: `git`, the scripts it started and
/// everything they started. No process outlives the test.
func runGit<Value>(
  _ arguments: [String], in directory: URL, sandbox: Sandbox,
  while body: () async throws -> Value = {}
) async throws -> (git: GitResult, value: Value) {
  let log = sandbox.directory.appending(path: "git-\(UUID().uuidString).log")
  let process = try GitProcess(
    executable: sandbox.git.executableURL, arguments: arguments,
    environment: sandbox.environment, directory: directory, log: log)
  let value: Value
  do {
    value = try await withTaskCancellationHandler(operation: body) { process.killGroup() }
  } catch {
    process.killGroup()
    _ = try await process.waitForExit()
    throw error
  }
  let status = try await withTaskCancellationHandler {
    try await process.waitForExit()
  } onCancel: {
    process.killGroup()
  }
  return (GitResult(status: status, output: try String(contentsOf: log, encoding: .utf8)), value)
}

/// A `git` process that leads a process group of its own.
private final class GitProcess: Sendable {
  let processID: pid_t

  init(
    executable: URL, arguments: [String], environment: [String: String], directory: URL,
    log: URL
  ) throws {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    posix_spawn_file_actions_addchdir(&actions, directory.path)

    let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      for string in argv + envp { free(string) }
    }
    var processID: pid_t = 0
    let status = posix_spawn(&processID, executable.path, &actions, &attributes, argv, envp)
    try #require(status == 0, "posix_spawn git: \(String(cString: strerror(status)))")
    self.processID = processID
  }

  /// Kills `git` and every process in its group.
  func killGroup() {
    killpg(processID, SIGKILL)
  }

  /// Waits until `git` has ended and returns its exit status, or 128 plus the signal that ended
  /// it.
  func waitForExit() async throws -> Int32 {
    let processID = processID
    return try await onThread {
      var status: Int32 = 0
      while waitpid(processID, &status, 0) < 0 {
        try #require(errno == EINTR, "waitpid: errno \(errno)")
      }
      let signal = status & 0x7f
      return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
  }
}

/// Waits until the process with `processID`, which need not be a child, has ended, and returns
/// whether it ended within ten seconds.
func waitUntilExited(processID: pid_t) async throws -> Bool {
  try await onThread {
    let queue = kqueue()
    try #require(queue >= 0, "kqueue: errno \(errno)")
    defer { close(queue) }
    var change = kevent(
      ident: UInt(processID), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
      fflags: NOTE_EXIT, data: 0, udata: nil)
    var event = kevent()
    var timeout = timespec(tv_sec: 10, tv_nsec: 0)
    let count = kevent(queue, &change, 1, &event, 1, &timeout)
    if count < 0 { return errno == ESRCH }
    if count == 1, event.flags & UInt16(EV_ERROR) != 0 { return event.data == Int(ESRCH) }
    return count == 1
  }
}

/// Runs `body` on a thread of its own, for calls that block until another process acts.
func onThread<Value: Sendable>(
  _ body: @escaping @Sendable () throws -> Value
) async throws -> Value {
  try await withCheckedThrowingContinuation { continuation in
    Thread { continuation.resume(with: Result(catching: body)) }.start()
  }
}
