import Foundation
import GitSupport
import MergeModel

/// What the patch of a window holds: the files of its comparison as read, or the files of a
/// window that compares several, which are read only when the patch is made.
///
/// Making the patch compares every file byte for byte and takes time in proportion to their
/// size, so it runs off the main actor.
struct PatchContent: Sendable {
  /// Where the files of the patch come from.
  enum Source: Sendable {
    /// Files read already.
    case files([UnifiedDiff.File])

    /// The files of a collection that changed, in the order of its list; with `reversed`, each
    /// leads from its newer side to its older one.
    case collected([CollectedFile], reversed: Bool)
  }

  let source: Source

  /// The number of files the patch holds, where a window of several files says it before the
  /// patch is made; `nil` for the patch of one file.
  var fileCount: Int? {
    switch source {
    case .files: nil
    case .collected(let files, _): files.count
    }
  }

  /// The patch in the bytes of the files.
  ///
  /// - Throws: ``PatchError/comparisonFailed(_:)`` if a comparison fails.
  @concurrent
  func data() async throws(PatchError) -> Data {
    let files = await files()
    do {
      return try UnifiedDiff.data(of: files)
    } catch {
      throw PatchError(error)
    }
  }

  /// The patch as text, each file decoded in its encoding.
  ///
  /// - Throws: ``PatchError/comparisonFailed(_:)`` if a comparison fails.
  @concurrent
  func text() async throws(PatchError) -> String {
    let files = await files()
    do {
      return try UnifiedDiff.text(of: files)
    } catch {
      throw PatchError(error)
    }
  }

  /// Writes the patch to the file at `url`, which it replaces as a whole.
  ///
  /// - Throws: ``PatchError/comparisonFailed(_:)`` if a comparison fails, or
  ///   ``PatchError/writingFailed(reason:)`` if the file cannot be written.
  @concurrent
  func write(to url: URL) async throws(PatchError) {
    let data = try await data()
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw .writingFailed(reason: error.localizedDescription)
    }
  }

  /// The files of the patch, read where they are not.
  @concurrent
  private func files() async -> [UnifiedDiff.File] {
    switch source {
    case .files(let files):
      return files
    case .collected(let collected, let reversed):
      return collected.map { file in
        let (old, new) = reversed ? (file.new, file.old) : (file.old, file.new)
        return UnifiedDiff.File(
          old: Self.side(reading: old, as: file.path), new: Self.side(reading: new, as: file.path),
          names: .path(file.path))
      }
    }
  }

  /// The side of a patch for `file`, read from disk: missing for `/dev/null`, the side of a new
  /// or a deleted file, and unreadable if it cannot be read.
  private static func side(reading file: SessionFile, as path: String) -> UnifiedDiff.File.Side {
    if FileOrigin(url: file.url) == .missing {
      return .missing
    }
    do {
      return .file(try SourceFile(contentsOf: file.url, label: path))
    } catch {
      return .unreadable
    }
  }
}

extension CollectedFile {
  /// Whether the patch of a window of several files holds the file: it changed, or a side cannot
  /// be read, which the patch notes as a file that differs.
  var belongsToPatch: Bool {
    if case .identical = change { false } else { true }
  }
}
