package import Foundation

/// A unified diff, as `git diff` and `diff -u` write it, read into its files and their hunks.
///
/// The patch keeps the bytes it was read from; its lines point into them. Lines keep their line
/// endings, CRLF too, so that a side built from them holds the bytes of the file it shows. Only
/// what a unified diff says about lines is read: modes, indexes and other headers of Git are
/// passed over.
package struct Patch: Sendable {
  /// The bytes the patch was read from, the first at index 0.
  package let bytes: Data

  /// The files the patch changes, in its order, without those whose mode alone changes.
  package let files: [File]

  /// The bytes of `line`: its text with its line ending, unless the file ends there without one.
  package func content(of line: Line) -> Data {
    bytes[line.bytes]
  }
}

extension Patch {
  /// A file of a patch: the names of its sides and the hunks that change it.
  package struct File: Sendable, Hashable {
    /// The path of the older side, without the prefix `a/` of Git; `nil` for a file the patch
    /// adds, whose older side is `/dev/null`.
    package var oldPath: String?

    /// The path of the newer side, without the prefix `b/` of Git; `nil` for a file the patch
    /// deletes, whose newer side is `/dev/null`.
    package var newPath: String?

    /// Whether the patch only says that the file differs, as for a binary file.
    package var isBinary: Bool

    /// The hunks, in their order.
    package var hunks: [Hunk]

    /// Describes a file.
    package init(oldPath: String?, newPath: String?, isBinary: Bool = false, hunks: [Hunk] = []) {
      self.oldPath = oldPath
      self.newPath = newPath
      self.isBinary = isBinary
      self.hunks = hunks
    }
  }

  /// A run of lines that a patch changes, with the context around them.
  package struct Hunk: Sendable, Hashable {
    /// The lines of the older file that the hunk covers, as its header gives them.
    package var old: LineRange

    /// The lines of the newer file that the hunk covers, as its header gives them.
    package var new: LineRange

    /// The lines of the hunk, in their order: context, removed and added.
    package var lines: [Line]

    /// Describes a hunk.
    package init(old: LineRange, new: LineRange, lines: [Line]) {
      self.old = old
      self.new = new
      self.lines = lines
    }
  }

  /// The lines of a file that a hunk covers.
  package struct LineRange: Sendable, Hashable {
    /// The number the header gives: the first line, counted from 1, or the line after which the
    /// hunk stands if it covers no lines of the file.
    package var start: Int

    /// The number of lines.
    package var count: Int

    /// Describes the lines a header gives.
    package init(start: Int, count: Int) {
      self.start = start
      self.count = count
    }

    /// The lines covered, counted from 0.
    package var lines: Range<Int> {
      let first = count == 0 ? start : start - 1
      return first..<first + count
    }
  }

  /// A line of a hunk.
  package struct Line: Sendable, Hashable {
    /// What a line of a hunk is.
    package enum Kind: Sendable, Hashable {
      /// A line both files share.
      case context

      /// A line of the older file that the newer one lacks.
      case removed

      /// A line of the newer file that the older one lacks.
      case added
    }

    /// What the line is.
    package var kind: Kind

    /// Where its bytes lie in the bytes of the patch, after the sign.
    package var bytes: Range<Int>

    /// Describes a line.
    package init(kind: Kind, bytes: Range<Int>) {
      self.kind = kind
      self.bytes = bytes
    }
  }
}
