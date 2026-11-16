import Foundation

/// A large comparison or merge that the measurements open: generated text, the same in every
/// run, so that two runs measure the same files.
struct LargeFileCase: Sendable {
  /// How the files differ.
  enum Kind: Sendable {
    /// Code with every 50th line changed, three lines added every 500 and every 700th removed.
    case manySmallChanges
    /// Code with five changes of 2 % of the file each: two replaced, two added, one removed.
    case fewLargeChanges
    /// Lines of about 1,900 characters, every 20th changed.
    case longLines
    /// A JSON array of 50,000 entries on a single line, 50 values changed.
    case singleLine
    /// A merge as `big` of `Scripts/make-test-repo.sh` makes it: lines `line n`, every 1,250th
    /// changed on both sides, each into a conflict.
    case conflictingLines
  }

  /// The name the measurements go by, which the environment chooses.
  let name: String

  /// The number of lines of the base, or of the older file.
  let lineCount: Int

  let kind: Kind

  /// Every case that can be measured.
  static let all = [
    LargeFileCase(name: "small-10k", lineCount: 10_000, kind: .manySmallChanges),
    LargeFileCase(name: "large-10k", lineCount: 10_000, kind: .fewLargeChanges),
    LargeFileCase(name: "small-100k", lineCount: 100_000, kind: .manySmallChanges),
    LargeFileCase(name: "large-100k", lineCount: 100_000, kind: .fewLargeChanges),
    LargeFileCase(name: "small-500k", lineCount: 500_000, kind: .manySmallChanges),
    LargeFileCase(name: "large-500k", lineCount: 500_000, kind: .fewLargeChanges),
    LargeFileCase(name: "long-5k", lineCount: 5_000, kind: .longLines),
    LargeFileCase(name: "oneline-2mb", lineCount: 1, kind: .singleLine),
    LargeFileCase(name: "big", lineCount: 50_000, kind: .conflictingLines),
    LargeFileCase(name: "big-500k", lineCount: 500_000, kind: .conflictingLines),
  ]

  /// Whether the case is a merge rather than a comparison of two files.
  var isMerge: Bool { kind == .conflictingLines }

  /// The extension of the files' names, by which the window picks the syntax.
  var fileExtension: String {
    switch kind {
    case .manySmallChanges, .fewLargeChanges, .longLines: "swift"
    case .singleLine: "json"
    case .conflictingLines: "txt"
    }
  }

  /// Two texts to search for, each of which the files hold: a rare one, with a match or two in
  /// each file, and a common one, with many thousands.
  var searchTexts: (rare: String, common: String) {
    switch kind {
    case .manySmallChanges, .fewLargeChanges: ("\"entry-4242\"", "compute")
    case .longLines: ("\"w4250-75\"", "\"v1")
    case .singleLine: ("\"entry-4242\"", "value")
    case .conflictingLines: ("line 31250 from", "line 1")
    }
  }

  /// The texts of the files: the older and the newer one of a comparison, or the base, A and B
  /// of a merge.
  func texts() -> (base: String?, a: String, b: String) {
    switch kind {
    case .manySmallChanges: Self.joined(manySmallChanges())
    case .fewLargeChanges: Self.joined(fewLargeChanges())
    case .longLines: Self.joined(longLines())
    case .singleLine: (nil, Self.json(changed: false) + "\n", Self.json(changed: true) + "\n")
    case .conflictingLines: conflictingLines()
    }
  }

  private static func joined(_ lines: (old: [String], new: [String])) -> (String?, String, String) {
    (nil, lines.old.joined(separator: "\n") + "\n", lines.new.joined(separator: "\n") + "\n")
  }

  private static func codeLine(_ index: Int) -> String {
    switch index % 10 {
    case 0: "  func step\(index)(value: Int) -> Int {"
    case 9: "  }"
    case 5: "    // Keeps \(index) in range, as the caller expects."
    default:
      "    let item\(index) = compute(\(index % 97), name: \"entry-\(index)\", scale: \(index % 13))"
    }
  }

  private static func changed(_ line: String) -> String {
    line.contains("compute(")
      ? line.replacingOccurrences(of: "compute(", with: "measure(")
      : line + " // changed"
  }

  private func manySmallChanges() -> (old: [String], new: [String]) {
    var old: [String] = []
    var new: [String] = []
    old.reserveCapacity(lineCount)
    new.reserveCapacity(lineCount)
    for index in 0..<lineCount {
      let line = Self.codeLine(index)
      old.append(line)
      guard index % 700 != 350 else { continue }
      new.append(index % 50 == 25 ? Self.changed(line) : line)
      if index % 500 == 100 {
        for added in 0..<3 {
          new.append("    let added\(index)_\(added) = compute(\(added), name: \"new\")")
        }
      }
    }
    return (old, new)
  }

  private func fewLargeChanges() -> (old: [String], new: [String]) {
    var old: [String] = []
    var new: [String] = []
    let size = max(100, lineCount / 50)
    let starts = [0.1, 0.3, 0.5, 0.7, 0.9].map { Int(Double(lineCount) * $0) }
    var index = 0
    while index < lineCount {
      switch starts.firstIndex(of: index) {
      case 0?, 3?:
        for replaced in index..<(index + size) {
          old.append(Self.codeLine(replaced))
          new.append(Self.changed(Self.codeLine(replaced)))
        }
        index += size
      case 1?, 4?:
        for added in 0..<size {
          new.append("    let inserted\(index)_\(added) = compute(\(added), name: \"new\")")
        }
        old.append(Self.codeLine(index))
        new.append(Self.codeLine(index))
        index += 1
      case 2?:
        for removed in index..<(index + size) {
          old.append(Self.codeLine(removed))
        }
        index += size
      default:
        old.append(Self.codeLine(index))
        new.append(Self.codeLine(index))
        index += 1
      }
    }
    return (old, new)
  }

  private func longLines() -> (old: [String], new: [String]) {
    func line(_ index: Int, changed: Bool) -> String {
      let items = (0..<150).map { item in
        changed && item == 75 ? "\"w\(index)-\(item)\"" : "\"v\(index)-\(item)\""
      }
      return "    let row\(index) = [" + items.joined(separator: ", ") + "]"
    }
    return (
      (0..<lineCount).map { line($0, changed: false) },
      (0..<lineCount).map { line($0, changed: $0 % 20 == 10) }
    )
  }

  private static func json(changed: Bool) -> String {
    let entries = (0..<50_000).map { entry in
      let value = changed && entry % 1000 == 500 ? entry + 1 : entry
      return "{\"id\":\(entry),\"name\":\"entry-\(entry)\",\"value\":\(value)}"
    }
    return "[" + entries.joined(separator: ",") + "]"
  }

  private func conflictingLines() -> (base: String?, a: String, b: String) {
    func text(changedBy suffix: String?) -> String {
      (1...lineCount).map { number in
        guard let suffix, number % 1250 == 0 else { return "line \(number)" }
        return "line \(number) \(suffix)"
      }.joined(separator: "\n") + "\n"
    }
    // A is the side being merged in and B the side merged into, as `git mergetool` hands them.
    return (text(changedBy: nil), text(changedBy: "from feature"), text(changedBy: "from main"))
  }
}
