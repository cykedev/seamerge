import AppKit
import GitSupport
import MergeModel

/// The title and subtitle of a merge window: the name of the file, how many changes each side
/// brings, and how far the Git operation has come.
struct SessionSummary: Equatable {
  /// The title: the name of the file that the result is written to.
  let title: String

  /// The parts of the subtitle in the order they stand; the operation is the first to go when
  /// the window is narrow.
  let changes: String
  let operation: String?
  let remainingFiles: String?

  /// Summarizes `changes` of a merge in `context`.
  init(changes: SessionChanges, context: SessionContext) {
    let session = changes.session
    let file = session.file(for: .b)
    title =
      context.resultURL?.lastPathComponent ?? file?.url?.lastPathComponent ?? file?.label ?? ""
    self.changes = [Self.changeCounts(of: changes), Self.modeNote(for: session.options.mode)]
      .compactMap(\.self).joined(separator: Self.separator)
    operation = context.git?.rebaseProgress.map { progress in
      String(
        localized:
          "Rebase onto \(SideHeader.text(of: progress.targetName)) · Commit \(progress.commitNumber) of \(progress.commitCount)",
        bundle: .module,
        comment: "Subtitle: how far a rebase has come, such as Rebase onto main · Commit 3 of 7.")
    }
    remainingFiles = context.git?.remainingConflictedFileCount.flatMap { count in
      count > 0
        ? String(
          localized: "\(count) more files with conflicts", bundle: .module,
          comment: "Subtitle: how many other files of the operation still have conflicts.")
        : nil
    }
  }

  /// The whole subtitle, as the help tag and VoiceOver give it.
  var fullSubtitle: String {
    [changes, operation, remainingFiles].compactMap(\.self).joined(separator: Self.separator)
  }

  /// The longest subtitle that fits in `width` points in `font`: the whole one, then without the
  /// operation, then the changes alone.
  func subtitle(fittingWidth width: CGFloat, font: NSFont) -> String {
    let candidates = [
      fullSubtitle,
      [changes, remainingFiles].compactMap(\.self).joined(separator: Self.separator),
      changes,
    ]
    return candidates.first { candidate in
      (candidate as NSString).size(withAttributes: [.font: font]).width <= width
    } ?? changes
  }

  /// The changes of each side, such as "3 changes from A · 5 from B".
  private static func changeCounts(of changes: SessionChanges) -> String {
    let (a, b) = (changes.changeCount(of: .a), changes.changeCount(of: .b))
    guard a > 0 || b > 0 else {
      return String(
        localized: "No changes", bundle: .module,
        comment: "Subtitle: neither side changed the base.")
    }
    return String(
      localized: "\(a) changes from A", bundle: .module,
      comment: "Subtitle: the changes of the incoming side, such as 3 changes from A.")
      + separator
      + String(
        localized: "\(b) from B", bundle: .module,
        comment: "Subtitle: the changes of the own side after those of A, such as 5 from B.")
  }

  /// The mode of the comparison where it differs from the mode a window compares in by default,
  /// or `nil` if it compares in that mode.
  private static func modeNote(for mode: ComparisonMode) -> String? {
    guard mode != .windowDefault else { return nil }
    return switch mode {
    case .exact:
      String(
        localized: "Compared exactly", bundle: .module,
        comment: "Subtitle: the comparison counts every byte, whitespace and line endings too.")
    case .ignoreLineEndings:
      String(
        localized: "Line endings ignored", bundle: .module,
        comment: "Subtitle: the comparison treats LF, CRLF and CR as equal.")
    case .ignoreWhitespaceAmount:
      String(
        localized: "Whitespace changes ignored", bundle: .module,
        comment: "Subtitle: the comparison ignores how much whitespace there is.")
    case .ignoreAllWhitespace:
      String(
        localized: "All whitespace ignored", bundle: .module,
        comment: "Subtitle: the comparison ignores spaces and tabs entirely.")
    }
  }

  /// What stands between the parts of the subtitle.
  private static let separator = " · "
}
