import AppKit
import FolderCompare
import GitSupport
import MergeModel

/// The title and subtitle of a session window: the name of the file, how many changes each side
/// of a merge brings, how far the Git operation has come, and which file of a run of
/// `git difftool` a comparison shows.
struct SessionSummary: Equatable {
  /// The title: the name of the file that the result of a merge is written to, the path in the
  /// repository of the file a comparison from Git or Tower shows, or else the names of the files
  /// a comparison shows.
  let title: String

  /// The parts of the subtitle in the order they stand; the operation is the first to go when
  /// the window is narrow, then the folders compared, then where the file stands among the files
  /// of the window.
  let changes: String
  let operation: String?
  let fileProgress: String?
  let folders: String?

  /// Summarizes `changes` in `context`, with the sides of a comparison where `arrangement` puts
  /// them, and names the comparison mode where it differs from `startMode`, that of a new window,
  /// and the ignore rules if they passed over a difference, as `ignoredDifferences` tell; while
  /// the files `isComparing` for the first time, it counts no changes yet.
  init(
    changes: SessionChanges, context: SessionContext, arrangement: PaneArrangement,
    startMode: ComparisonMode, ignoredDifferences: IgnoredDifferences?, isComparing: Bool = false
  ) {
    let session = changes.session
    // A rule that empties a whole file leaves no change; the note says why.
    let rulesNote =
      ignoredDifferences?.includesDifferencesThatRulesIgnore == true
      ? String(
        localized: "Ignore rules applied", bundle: .module,
        comment: "Subtitle: ignore rules left out text in which the files differ.")
      : nil
    let modeNote = [Self.modeNote(for: session.options.mode, startMode: startMode), rulesNote]
      .compactMap(\.self).joined(separator: Self.separator)
    let modeNotes = modeNote.isEmpty ? nil : modeNote
    let name: String
    if arrangement.showsResult {
      let file = session.inputs.b
      name = context.resultURL?.lastPathComponent ?? file.url?.lastPathComponent ?? file.label
      self.changes = [isComparing ? nil : Self.changeCounts(of: changes), modeNotes]
        .compactMap(\.self).joined(separator: Self.separator)
    } else {
      name =
        context.difftool?.path
        ?? Self.title(of: arrangement.sourceRoles.compactMap { session.inputs[$0] })
      self.changes = modeNote
    }
    // A label from the command line may hold a tab or a line break; the title stands on one
    // line, as the headers do.
    title = SideHeader.singleLine(name)
    operation = context.git?.rebaseProgress.map { progress in
      String(
        localized:
          "Rebase onto \(SideHeader.text(of: progress.targetName)) · Commit \(progress.commitNumber) of \(progress.commitCount)",
        bundle: .module,
        comment: "Subtitle: how far a rebase has come, such as Rebase onto main · Commit 3 of 7.")
    }
    let remainingFiles = context.git?.remainingConflictedFileCount.flatMap { count in
      count > 0
        ? String(
          localized: "\(count) more files with conflicts", bundle: .module,
          comment: "Subtitle: how many other files of the operation still have conflicts.")
        : nil
    }
    let filePosition = context.difftool?.filePosition.map { position in
      String(
        localized: "File \(position.number) of \(position.count)", bundle: .module,
        comment: "Subtitle: which file of a git difftool run is compared, such as File 3 of 12.")
    }
    fileProgress = remainingFiles ?? filePosition
    // Without a file in view, the title names the folders already.
    folders = context.difftool == nil ? nil : context.folders?.title
  }

  /// The whole subtitle, as the help tag and VoiceOver give it.
  var fullSubtitle: String {
    Self.joined([changes, operation, fileProgress, folders])
  }

  /// The parts that are there, with the separator between them.
  private static func joined(_ parts: [String?]) -> String {
    parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: separator)
  }

  /// The title of a comparison of `files`, from left to right: their name if both have the
  /// same, and both names otherwise.
  ///
  /// The names come from the labels, since Git compares temporary copies whose names are made
  /// up.
  /// The title of a comparison of `files`: the name both share, or both names; a missing side
  /// of a new or a deleted file has none.
  private static func title(of files: [SourceFile]) -> String {
    let names = files.filter { file in file.url.map { FileOrigin(url: $0) != .missing } ?? true }
      .map { ($0.label as NSString).lastPathComponent }
    guard let first = names.first, let last = names.last, first != last else {
      return names.first ?? ""
    }
    return String(
      localized: "\(first) ↔ \(last)", bundle: .module,
      comment: "The names of the left and the right file of a comparison, in a title or list.")
  }

  /// The longest subtitle that fits in `width` points in `font`: the whole one, then without the
  /// operation, then without the folders, then the changes alone.
  func subtitle(fittingWidth width: CGFloat, font: NSFont) -> String {
    let candidates = [
      fullSubtitle, Self.joined([changes, fileProgress, folders]),
      Self.joined([changes, fileProgress]), changes,
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

  /// The mode of the comparison where it differs from `startMode`, the mode a new window
  /// compares in, or `nil` if it compares in that mode.
  private static func modeNote(for mode: ComparisonMode, startMode: ComparisonMode) -> String? {
    guard mode != startMode else { return nil }
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
