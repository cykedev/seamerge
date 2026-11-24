import Foundation
import GitSupport
public import MergeModel

/// A comparison of two files that cannot be compared, such as one of an image, with what its
/// window says in place of their lines.
///
/// A run of `git difftool` goes on past such a file: its window names the files and says why,
/// and closing it lets Git compare the next one.
public struct UnavailableComparison: Sendable {
  /// The older file, on the left.
  public let old: SessionFile

  /// The newer file, on the right.
  public let new: SessionFile

  /// Why the files cannot be compared.
  public let reason: SessionLoadingError

  /// Describes the comparison of `old` with `new`, which failed for `reason`.
  public init(old: SessionFile, new: SessionFile, reason: SessionLoadingError) {
    self.old = old
    self.new = new
    self.reason = reason
  }

  /// The comparison of the two files without their lines, which gives the window its headers.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if even that fails.
  func emptySession() async throws(SessionLoadingError) -> Session {
    do {
      return try await Session.diff(
        old: SourceFile(bytes: Data(), label: old.label),
        new: SourceFile(bytes: Data(), label: new.label), mode: .windowDefault)
    } catch {
      throw .comparisonFailed
    }
  }

  /// What the window says first: that it cannot show the differences, and of which file.
  var title: String {
    String(
      localized: "Seamerge can’t show the differences of “\(Self.name(of: new))”", bundle: .module,
      comment: "Comparison window: the files cannot be compared, such as of “logo.png”.")
  }

  /// What the window says below: why, what to do about it, and in a run of `git difftool` with
  /// files left how to go on.
  func message(in context: SessionContext) -> String {
    let reason =
      switch reason {
      case .binaryFile(let url):
        String(
          localized: "“\(name(of: url))” isn’t a text file. Open it in the app that made it.",
          bundle: .module, comment: "Comparison window: a file is binary, and what to do.")
      case .unreadableFile(let url):
        String(
          localized:
            "Seamerge can’t read “\(name(of: url))”. Check that it exists and that you may read it.",
          bundle: .module, comment: "Comparison window: a file cannot be read, and what to do.")
      case .filesTooLarge:
        String(
          localized: "The files are too large to compare. Quit other apps to free memory.",
          bundle: .module, comment: "Comparison window: the files do not fit in memory.")
      case .comparisonFailed:
        String(
          localized: "The comparison failed. Try again, or use another tool for this file.",
          bundle: .module, comment: "Comparison window: the comparison failed for another reason.")
      case .unreadablePatch:
        String(
          localized: "The patch can’t be read. Open a unified diff, as git diff writes it.",
          bundle: .module, comment: "Comparison window: a patch is not a unified diff.")
      }
    guard context.difftool.map(\.hasFilesAfterThisOne) == true else { return reason }
    return reason + " "
      + String(
        localized: "Close the window to go on to the next file.", bundle: .module,
        comment: "Comparison window: closing it lets git difftool compare the next file.")
  }

  /// The name of the file at `url` as the headers show it.
  private func name(of url: URL) -> String {
    Self.name(of: [old, new].first { $0.url == url } ?? SessionFile(url: url, label: ""))
  }

  /// The name of `file` without its folders; Git compares temporary copies, so the label names
  /// it where there is one.
  private static func name(of file: SessionFile) -> String {
    file.label.isEmpty ? file.url.lastPathComponent : (file.label as NSString).lastPathComponent
  }
}

extension DifftoolContext {
  /// Whether Git compares more files after this one, as far as it tells.
  var hasFilesAfterThisOne: Bool {
    filePosition.map { $0.number < $0.count } ?? true
  }
}
