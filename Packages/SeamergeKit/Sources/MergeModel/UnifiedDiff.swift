public import Foundation
import TextIO

/// Files compared and written as a unified diff, as `git diff` writes it, which `git apply` and
/// `patch -p1` take.
///
/// Each pair of files is compared anew, byte for byte and without ignore rules, whatever mode a
/// session compares them in: a patch that passes over a difference would not make the newer
/// file. The lines are written in the bytes of their files, with their line endings, CRLF too,
/// and a last line without a line break is marked as Git marks it. A file whose lines cannot be
/// shown, such as one in UTF-16, takes a single line that says that it differs, as Git writes
/// for a binary file.
public enum UnifiedDiff {
  /// The number of unchanged lines that stand before and after each change.
  static let contextLineCount = 3

  /// The unified diff of `files`, in their order, in the bytes of the files; files whose sides
  /// hold the same bytes are left out.
  ///
  /// The work takes time in proportion to the size of the files, so it is best done off the main
  /// thread.
  ///
  /// - Throws: ``MergeModelError/outOfMemory`` or ``MergeModelError/comparisonFailed`` if a
  ///   comparison fails. A file too large to compare is written as one that differs.
  public static func data(of files: [File]) throws(MergeModelError) -> Data {
    try write(files, into: ByteOutput()).data
  }

  /// The unified diff of `files` as text, the lines of each file decoded in the encoding it was
  /// read in, for a reader of text such as the pasteboard.
  ///
  /// It is the text of ``data(of:)``, and the same bytes where every file is in UTF-8. Bytes that
  /// are not valid in the encoding of their file become U+FFFD.
  ///
  /// - Throws: ``MergeModelError/outOfMemory`` or ``MergeModelError/comparisonFailed`` if a
  ///   comparison fails.
  public static func text(of files: [File]) throws(MergeModelError) -> String {
    try write(files, into: DecodedOutput()).text
  }

  /// Writes the headers and the changes of each file of `files` that has any to `output`.
  private static func write<Output: UnifiedDiffOutput>(
    _ files: [File], into output: Output
  ) throws(MergeModelError) -> Output {
    var output = output
    for file in files where file.hasChanges {
      try write(file, into: &output)
    }
    return output
  }

  /// Writes the headers and the changes of `file`.
  private static func write<Output: UnifiedDiffOutput>(
    _ file: File, into output: inout Output
  ) throws(MergeModelError) {
    var lines: Lines?
    if let old = file.old.textFile, let new = file.new.textFile {
      do {
        lines = try Lines(old: old, new: new)
      } catch .inputTooLarge {
        lines = nil
      }
    }
    let oldName = file.old.isMissing ? devNull : file.names.old
    let newName = file.new.isMissing ? devNull : file.names.new
    if case .path = file.names {
      output.append(line: "diff --git \(file.names.old) \(file.names.new)")
      // Git takes /dev/null as a side only where the mode of the file says it is new or deleted.
      if file.old.isMissing {
        output.append(line: "new file mode \(regularFileMode)")
      } else if file.new.isMissing {
        output.append(line: "deleted file mode \(regularFileMode)")
      }
    }
    guard let lines else {
      output.append(line: "Binary files \(oldName) and \(newName) differ")
      return
    }
    let hunks = lines.hunks
    guard !hunks.isEmpty else { return }
    output.append(line: "--- \(oldName)\(nameEnd(oldName))")
    output.append(line: "+++ \(newName)\(nameEnd(newName))")
    for hunk in hunks {
      lines.write(hunk, into: &output)
    }
  }

  /// What stands after a name in the lines `---` and `+++`: a tab after a name with a space,
  /// as Git writes it, so that `patch` takes the whole name rather than its first word.
  private static func nameEnd(_ name: String) -> String {
    name.contains(" ") ? "\t" : ""
  }

  /// The name of the side of a file that does not exist.
  private static let devNull = "/dev/null"

  /// The mode Git gives an ordinary file that is not executable.
  private static let regularFileMode = "100644"
}
