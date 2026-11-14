import Foundation
import GitSupport
import MergeModel
import os

/// A file to read for a session, with the label its header shows where nothing else names its
/// side.
public struct SessionFile: Sendable, Hashable {
  /// Where the file is.
  public var url: URL

  /// The name of the side when nothing else names it.
  public var label: String

  /// Names the file at `url`, which shows as `label` where nothing else names its side.
  public init(url: URL, label: String) {
    self.url = url
    self.label = label
  }
}

extension Session {
  /// Reads the files and merges them in the comparison mode `mode`, away from the main actor.
  ///
  /// - Throws: ``SessionLoadingError`` with the file that cannot be read or is not text, or why
  ///   the files cannot be compared.
  @concurrent
  public static func loadMerge(
    base: SessionFile?, a: SessionFile, b: SessionFile, mode: ComparisonMode
  ) async throws(SessionLoadingError) -> Session {
    let baseFile = try base.map(read)
    let (aFile, bFile) = (try read(a), try read(b))
    do {
      return try await merge(
        base: baseFile, a: aFile, b: bFile, options: ComparisonOptions(mode: mode))
    } catch {
      throw SessionLoadingError(error, files: [.base: base, .a: a, .b: b].compactMapValues(\.self))
    }
  }

  /// Reads the files and compares the older file `old` with the newer file `new` in the
  /// comparison mode `mode`, away from the main actor.
  ///
  /// - Throws: ``SessionLoadingError`` with the file that cannot be read or is not text, or why
  ///   the files cannot be compared.
  @concurrent
  public static func loadDiff(
    old: SessionFile, new: SessionFile, mode: ComparisonMode
  ) async throws(SessionLoadingError) -> Session {
    let (oldFile, newFile) = (try read(old), try read(new))
    do {
      return try await diff(old: oldFile, new: newFile, mode: mode)
    } catch {
      throw SessionLoadingError(error, files: [.a: old, .b: new])
    }
  }

  /// Reads `file`; `/dev/null`, the missing side of a new or a deleted file, is empty, since it
  /// cannot be mapped like a file.
  private static func read(_ file: SessionFile) throws(SessionLoadingError) -> SourceFile {
    if FileOrigin(url: file.url) == .missing {
      return SourceFile(bytes: Data(), label: file.label, url: file.url)
    }
    do {
      return try SourceFile(contentsOf: file.url, label: file.label)
    } catch {
      loadingLogger.error(
        "Cannot read \(file.url.path(percentEncoded: false)): \(String(describing: error))")
      throw .unreadableFile(file.url)
    }
  }
}

private let loadingLogger = Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI")
