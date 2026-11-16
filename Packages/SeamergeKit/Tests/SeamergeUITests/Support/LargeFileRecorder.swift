import Darwin
import Foundation

/// Writes what a measurement of a large file finds, one line per value, as it finds it: into the
/// file that `SEAMERGE_MEASURE_OUTPUT` names, or to standard error.
///
/// Each line holds, separated by tabs, the case, the metric, the value, its unit, the time in
/// seconds since 1970 and the time of day. A metric that starts with `#` marks the progress:
/// `#phase` with the name of the phase that begins, `#done` once every phase is over. Lines are
/// written at once, so that what a run found before it was stopped stays.
@MainActor
final class LargeFileRecorder {
  private let caseName: String
  private let output: FileHandle
  private let timeOfDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  /// A recorder for the measurements of `caseName`.
  ///
  /// - Throws: The error of the file system if the output file cannot be opened.
  init(caseName: String) throws {
    self.caseName = caseName
    if let path = ProcessInfo.processInfo.environment["SEAMERGE_MEASURE_OUTPUT"] {
      let url = URL(filePath: path)
      if !FileManager.default.fileExists(atPath: url.path) {
        try Data().write(to: url)
      }
      output = try FileHandle(forWritingTo: url)
      try output.seekToEnd()
    } else {
      output = .standardError
    }
  }

  /// Records `value` of `metric` in `unit`.
  func record(_ metric: String, _ value: Double, unit: String = "ms") {
    write(metric, String(format: "%.2f", value), unit: unit)
  }

  /// Records `duration` of `metric` in milliseconds.
  func record(_ metric: String, _ duration: Duration) {
    record(metric, Self.milliseconds(duration))
  }

  /// Marks the beginning of `phase`.
  func begin(_ phase: String) {
    write("#phase", phase, unit: "-")
  }

  /// Marks that every phase is over.
  func finish() {
    write("#done", "-", unit: "-")
  }

  /// Records the physical footprint of the process now and its peak so far, after `phase`.
  func recordMemory(after phase: String) {
    let footprint = Self.footprint()
    record("memory-\(phase)", footprint.now, unit: "MB")
    record("memory-peak-\(phase)", footprint.peak, unit: "MB")
  }

  /// The physical footprint of the process and its peak since it started, in MB.
  static func footprint() -> (now: Double, peak: Double) {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    precondition(result == 0, "The usage of the own process is always known: \(errno)")
    let megabyte = 1_048_576.0
    return (
      Double(usage.ri_phys_footprint) / megabyte,
      Double(usage.ri_lifetime_max_phys_footprint) / megabyte
    )
  }

  /// `duration` in milliseconds.
  static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }

  private func write(_ metric: String, _ value: String, unit: String) {
    let now = Date()
    let fields = [
      caseName, metric, value, unit, String(format: "%.3f", now.timeIntervalSince1970),
      timeOfDay.string(from: now),
    ]
    output.write(Data((fields.joined(separator: "\t") + "\n").utf8))
  }
}
