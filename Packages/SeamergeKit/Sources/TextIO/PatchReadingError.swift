/// Why a text cannot be read as a unified diff.
///
/// Each case that concerns a line carries its number, counted from 1, so that a message can point
/// at it.
package enum PatchReadingError: Error, Sendable, Hashable {
  /// The text is a combined diff of a merge, `diff --cc` or `diff --combined`, which compares
  /// more than two files.
  case combinedDiff(line: Int)

  /// The text holds no file of a unified diff, as a context diff or a normal diff does not.
  case notUnifiedDiff

  /// The header of a hunk is not of the form `@@ -start,count +start,count @@`.
  case malformedHunkHeader(line: Int)

  /// A hunk comes before the lines `---` and `+++` that name its file.
  case hunkWithoutFile(line: Int)

  /// The hunk whose header is at the line ends before it holds as many lines as its header
  /// says, as a patch that was cut off does.
  case truncatedHunk(line: Int)

  /// The hunk whose header is at the line holds other lines than its header says: a line of
  /// the hunk follows once the header's counts are used up, or a line counts on a side whose
  /// count is used up.
  case hunkLengthMismatch(line: Int)

  /// A name in the header of a file, starting with a quote, does not end as Git quotes names.
  case malformedFileName(line: Int)
}
