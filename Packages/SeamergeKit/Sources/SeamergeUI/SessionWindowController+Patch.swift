import AppKit
import GitSupport
import MergeModel

/// The changes of a comparison as a unified diff, exported to a file or copied.
///
/// The patch counts every byte, whatever the comparison mode and the ignore rules of the window,
/// and leads from the left side to the right one, so that Swap Sides turns it round. A window of
/// several files writes all files that changed, in the order of its list and whatever its filter
/// shows.
extension SessionWindowController {
  /// Writes the patch to a file that the user chooses.
  @objc func exportPatch(_ sender: Any?) {
    guard canPerform(.exportPatch) else { return }
    Task { await exportPatchChoosingPlace() }
  }

  /// Copies the patch as text.
  @objc func copyPatch(_ sender: Any?) {
    guard canPerform(.copyPatch) else { return }
    Task { await copyPatchToPasteboard() }
  }

  /// Asks where to write the patch and writes it there, and tells whether it did; a failure
  /// shows a sheet with the reason.
  @discardableResult
  func exportPatchChoosingPlace() async -> Bool {
    guard let window else { return false }
    let patch = patchContent
    guard
      let url = await prompts.choosePatchDestination(
        suggesting: suggestedPatchName, fileCount: patch.fileCount, in: window)
    else { return false }
    do {
      try await patch.write(to: url)
    } catch {
      await prompts.reportFailedPatch(error, exporting: url.lastPathComponent, in: window)
      return false
    }
    presentation.announce(
      String(
        localized: "Exported \(url.lastPathComponent)", bundle: .module,
        comment: "VoiceOver after exporting a patch, such as Exported story.txt.patch."))
    return true
  }

  /// Puts the patch on the pasteboard as text, says so to VoiceOver, and tells whether it did; a
  /// failure shows a sheet with the reason.
  @discardableResult
  func copyPatchToPasteboard() async -> Bool {
    let patch = patchContent
    let text: String
    do {
      text = try await patch.text()
    } catch {
      if let window {
        await prompts.reportFailedPatch(error, exporting: nil, in: window)
      }
      return false
    }
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let announcement =
      if let count = patch.fileCount {
        String(
          localized: "Copied the patch of \(count) files", bundle: .module,
          comment: "VoiceOver after copying the patch of a window of several files.")
      } else {
        String(
          localized: "Copied the patch", bundle: .module,
          comment: "VoiceOver after copying the patch of a comparison of two files.")
      }
    presentation.announce(announcement)
    return true
  }

  /// Whether the window has a patch to make: in a comparison of two files, files whose bytes
  /// differ and whose lines the patch can show; in a window of several files, one that changed.
  var hasPatch: Bool {
    guard let collection else { return comparisonHasPatch }
    return collection.files.contains(where: \.belongsToPatch)
  }

  /// Whether the comparison of two files in view has a patch, which compares the files byte for
  /// byte; `false` in a merge and in a window of several files.
  var shownComparisonHasPatch: Bool {
    guard collection == nil, binaryMerge == nil, unavailable == nil,
      presentation.changes.session.kind == .diff
    else { return false }
    let file = sessionPatchFile
    return file.hasChanges && file.showsLines
  }

  /// The files of the patch of the window as they stand now.
  var patchContent: PatchContent {
    guard let collection else { return PatchContent(source: .files([sessionPatchFile])) }
    return PatchContent(
      source: .collected(
        collection.files.filter(\.belongsToPatch), reversed: presentation.arrangement.origin == .b))
  }

  /// The file of the patch of a comparison of two files, from the left side to the right one.
  ///
  /// The headers name the file by its path in the repository if Git tells it, and else by the
  /// names of the sides.
  private var sessionPatchFile: UnifiedDiff.File {
    let arrangement = presentation.arrangement
    let (oldRole, newRole) = (arrangement.leadingRole, arrangement.trailingRole)
    let names: UnifiedDiff.Names =
      if let path = context.difftool?.path {
        .path(path)
      } else {
        .labels(old: sideName(of: oldRole), new: sideName(of: newRole))
      }
    return UnifiedDiff.File(old: patchSide(of: oldRole), new: patchSide(of: newRole), names: names)
  }

  /// The side of `role` in a patch: missing where the window compares with `/dev/null`, as for a
  /// new or a deleted file.
  private func patchSide(of role: Role) -> UnifiedDiff.File.Side {
    guard let file = presentation.changes.session.inputs[role] else { return .missing }
    if let url = file.url, FileOrigin(url: url) == .missing {
      return .missing
    }
    return .file(file)
  }

  /// The name of the side of `role` as its header shows it.
  private func sideName(of role: Role) -> String {
    presentation.headers[role]?.name ?? presentation.changes.session.inputs[role]?.label ?? ""
  }

  /// The name the choice of the place of the patch suggests: the names of two folders, a name
  /// for the files of a run of Git, or the name of the one file.
  var suggestedPatchName: String {
    let name: String
    if let folders = collection?.folders {
      let names = folders.distinctNames
      name = "\(names.left)-\(names.right)".replacingOccurrences(of: "/", with: "-")
    } else if collection != nil {
      name = String(
        localized: "changes", bundle: .module,
        comment: "The name suggested for the patch of the files of a run of Git, before .patch.")
    } else {
      let file = sessionPatchFile
      let path =
        switch file.names {
        case .path(let path): path
        case .labels(let old, let new): file.new.isMissing ? old : new
        }
      name = path.split(separator: "/").last.map(String.init) ?? path
    }
    return name + ".patch"
  }
}
