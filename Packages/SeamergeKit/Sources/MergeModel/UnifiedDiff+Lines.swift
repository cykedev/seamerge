import Foundation

extension UnifiedDiff {
  /// A side of a file whose lines a diff shows: its bytes and the encoding it was read in, or
  /// `nil` for a side that does not exist.
  struct TextFile {
    var bytes: Data
    var encoding: FileEncoding?
  }

  /// The lines of both sides of a file as an exact comparison splits them, at line feeds, and
  /// the hunks in which they differ.
  struct Lines {
    /// A run of changes close enough to share their context, and the lines it covers on each
    /// side, context included.
    struct Hunk {
      var old: Range<Int>
      var new: Range<Int>

      /// The changed blocks of the hunk, in order.
      var changes: [Block]
    }

    private let old: TextFile
    private let new: TextFile
    private let oldLineStarts: [Int]
    private let newLineStarts: [Int]
    private let changes: [Block]

    /// Compares the bytes of `old` and `new` byte for byte.
    ///
    /// - Throws: The error of the comparison.
    init(old: TextFile, new: TextFile) throws(MergeModelError) {
      let comparison = try EngineAdapter.diff(old: old.bytes, new: new.bytes, mode: .exact)
      guard let oldLineStarts = comparison.lineStarts[.a],
        let newLineStarts = comparison.lineStarts[.b]
      else {
        preconditionFailure("A comparison of two files splits both into lines")
      }
      self.old = old
      self.new = new
      self.oldLineStarts = oldLineStarts
      self.newLineStarts = newLineStarts
      changes = comparison.blocks.filter { $0.kind != .unchanged }
    }

    /// The hunks of the changes, each with up to ``UnifiedDiff/contextLineCount`` unchanged lines
    /// before and after it.
    ///
    /// Changes that fewer than twice as many unchanged lines part share a hunk, as in `git diff`,
    /// so that no line stands in two hunks.
    var hunks: [Hunk] {
      let context = UnifiedDiff.contextLineCount
      var groups: [[Block]] = []
      for change in changes {
        if let last = groups.last?.last, change.a.lowerBound - last.a.upperBound <= 2 * context {
          groups[groups.count - 1].append(change)
        } else {
          groups.append([change])
        }
      }
      return groups.compactMap { group in
        guard let first = group.first, let last = group.last else { return nil }
        // The lines before the first change and after the last are equal on both sides, so the
        // context is as long on each.
        let before = min(context, first.a.lowerBound, first.b.lowerBound)
        let after = min(
          context, oldLineCount - last.a.upperBound, newLineCount - last.b.upperBound)
        return Hunk(
          old: first.a.lowerBound - before..<last.a.upperBound + after,
          new: first.b.lowerBound - before..<last.b.upperBound + after, changes: group)
      }
    }

    /// Writes `hunk`: its header, then its unchanged lines with a space, its removed lines with a
    /// minus sign and its added lines with a plus sign before them.
    func write<Output: UnifiedDiffOutput>(_ hunk: Hunk, into output: inout Output) {
      output.append(line: "@@ -\(Self.header(of: hunk.old)) +\(Self.header(of: hunk.new)) @@")
      var oldLine = hunk.old.lowerBound
      for change in hunk.changes {
        writeLines(
          oldLine..<change.a.lowerBound, of: old, starts: oldLineStarts, as: " ", to: &output)
        writeLines(change.a, of: old, starts: oldLineStarts, as: "-", to: &output)
        writeLines(change.b, of: new, starts: newLineStarts, as: "+", to: &output)
        oldLine = change.a.upperBound
      }
      writeLines(
        oldLine..<hunk.old.upperBound, of: old, starts: oldLineStarts, as: " ", to: &output)
    }

    private var oldLineCount: Int { oldLineStarts.count - 1 }
    private var newLineCount: Int { newLineStarts.count - 1 }

    /// Writes `lines` of `file`, each after `sign`; a last line without a line break is followed
    /// by one and by the line that says so.
    private func writeLines<Output: UnifiedDiffOutput>(
      _ lines: Range<Int>, of file: TextFile, starts: [Int], as sign: Character,
      to output: inout Output
    ) {
      for line in lines {
        let start = file.bytes.startIndex
        let bytes = file.bytes[start + starts[line]..<start + starts[line + 1]]
        output.append(sign: sign, line: bytes, in: file.encoding)
        if bytes.last != UInt8(ascii: "\n") {
          output.append(line: "")
          output.append(line: "\\ No newline at end of file")
        }
      }
    }

    /// The range of a hunk header, `start,count`: the start counts from 1, and is the line before
    /// the hunk where it covers no lines; a count of 1 is left out.
    private static func header(of lines: Range<Int>) -> String {
      switch lines.count {
      case 0: "\(lines.lowerBound),0"
      case 1: "\(lines.lowerBound + 1)"
      default: "\(lines.lowerBound + 1),\(lines.count)"
      }
    }
  }
}
