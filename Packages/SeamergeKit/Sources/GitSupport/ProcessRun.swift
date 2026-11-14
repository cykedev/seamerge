import Darwin
import Foundation

/// A process as it ran: its process ID together with the moment it started, which together name
/// it even after the system has given the ID to another process.
///
/// `git difftool` runs one `git diff` that hands every file of a run to the tool in turn, so that
/// the files of one run share the `git diff` above them.
public struct ProcessRun: Sendable, Hashable {
  /// The ID of the process.
  public var processID: Int32

  /// When the process started, in microseconds since 1970.
  public var startTime: Int64

  /// Creates the description of a process that started at `startTime`.
  public init(processID: Int32, startTime: Int64) {
    self.processID = processID
    self.startTime = startTime
  }

  /// The process with `processID` as it runs now, or `nil` if there is none.
  public init?(processID: Int32) {
    guard let info = Self.info(of: processID) else { return nil }
    self.processID = processID
    startTime = Self.startTime(of: info)
  }

  /// Whether the process still runs: a process with the same ID started at the same moment.
  public var isRunning: Bool {
    ProcessRun(processID: processID) == self
  }

  /// The run of `git difftool` that started the process `processID`: the closest process above
  /// it that is neither a shell nor the script `git-difftool--helper`, or `nil` if there is none.
  ///
  /// Git starts the tool through a shell from `git-difftool--helper`, itself a shell script that
  /// `git diff` starts once for every file. Tower starts the tool through a shell script of its
  /// own, which the walk passes too.
  public static func difftoolRun(above processID: Int32 = getpid()) -> ProcessRun? {
    var current = Self.info(of: processID).map { $0.kp_eproc.e_ppid }
    while let id = current, id > 1, let info = Self.info(of: id) {
      if !shellNames.contains(Self.name(of: info)) {
        return ProcessRun(processID: id, startTime: Self.startTime(of: info))
      }
      current = info.kp_eproc.e_ppid
    }
    return nil
  }

  /// The names of the processes that only pass the call on: shells, among them those that run
  /// `git-difftool--helper` and the script of Tower.
  private static let shellNames: Set<String> = ["sh", "bash", "zsh", "dash", "ksh"]

  private static func info(of processID: Int32) -> kinfo_proc? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
    guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0,
      info.kp_proc.p_pid == processID
    else { return nil }
    return info
  }

  private static func startTime(of info: kinfo_proc) -> Int64 {
    let start = info.kp_proc.p_starttime
    return Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
  }

  private static func name(of info: kinfo_proc) -> String {
    withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}
