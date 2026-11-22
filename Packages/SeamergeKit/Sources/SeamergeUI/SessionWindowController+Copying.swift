import AppKit
import MergeModel
import PaneKit

/// Copying changes from one file of a comparison to the other: Copy to Right and Copy to Left
/// for the current change, from the Compare menu, their keys, the context menu or the buttons at
/// the seam, and Copy All Changes to Right and to Left.
extension SessionWindowController {
  /// Has the file on the right take the text of the left at the current block.
  @objc func copyToRight(_ sender: Any?) {
    copying = copy(.copyToRight, block: presentation.currentBlock)
  }

  /// Has the file on the left take the text of the right at the current block.
  @objc func copyToLeft(_ sender: Any?) {
    copying = copy(.copyToLeft, block: presentation.currentBlock)
  }

  /// Has the file on the right take the text of the left at every changed block.
  @objc func copyAllChangesToRight(_ sender: Any?) {
    copying = copy(.copyAllChangesToRight, block: nil)
  }

  /// Has the file on the left take the text of the right at every changed block.
  @objc func copyAllChangesToLeft(_ sender: Any?) {
    copying = copy(.copyAllChangesToLeft, block: nil)
  }

  /// The sides that changes may be copied to now: in a comparison whose lines the window shows,
  /// the side on the right or the left whose file may be written.
  var copyDirections: Set<PaneSeam.CopyDirection> {
    guard case .ready = phase, binaryMerge == nil, presentation.changes.session.kind == .diff,
      let writableSides
    else { return [] }
    let arrangement = presentation.arrangement
    var directions: Set<PaneSeam.CopyDirection> = []
    if writableSides.allowsCopyToRight(in: arrangement) {
      directions.insert(.toRight)
    }
    if writableSides.allowsCopyToLeft(in: arrangement) {
      directions.insert(.toLeft)
    }
    return directions
  }

  /// Whether a command that copies in `direction`, every change for `allChanges` or else the
  /// current one, has an effect now.
  func canCopy(_ direction: PaneSeam.CopyDirection, allChanges: Bool) -> Bool {
    canCopy(direction, block: allChanges ? nil : presentation.currentBlock, allChanges: allChanges)
  }

  /// Whether copying in `direction` has an effect now: of every changed block for
  /// `allChanges`, else of `block`.
  private func canCopy(
    _ direction: PaneSeam.CopyDirection, block: Int?, allChanges: Bool
  ) -> Bool {
    guard copyDirections.contains(direction), !comparisonSwitcher.isComparing,
      !diskWatch.isReloading
    else { return false }
    let blocks = presentation.changes.blocks
    guard !allChanges else { return blocks.contains { $0.kind == .changed } }
    return block.map { blocks.indices.contains($0) && blocks[$0].kind == .changed } ?? false
  }

  /// Decides once which files of the session may be written, as the window shows files it did
  /// not show before, and gives the seams their buttons.
  func updateCopyControls() {
    let inputs = presentation.changes.session.inputs
    let urls = [inputs.a.url, inputs.b.url]
    if urls != writableFileURLs || writableSides == nil {
      writableFileURLs = urls
      writableSides = inputs.a.url.flatMap { old in
        inputs.b.url.map { new in
          WritableSides(
            old: SessionFile(url: old, label: inputs.a.label),
            new: SessionFile(url: new, label: inputs.b.label), context: context)
        }
      }
    }
    // The single column has no seam; its menu, keys and context menu copy all the same.
    let directions = presentation.lineArrangement == .singleColumn ? [] : copyDirections
    if layout.copyDirections != directions {
      layout.copyDirections = directions
      presentation.showSeamBands()
    }
    let arrangement = presentation.arrangement
    let texts: [PaneSeam.CopyDirection: PaneSeam.CopyText] = [
      .toRight: copyText(.toRight, to: arrangement.trailingRole),
      .toLeft: copyText(.toLeft, to: arrangement.leadingRole),
    ]
    // A copy waits for no comparison under way, nor do its buttons.
    let enabled = !comparisonSwitcher.isComparing && !diskWatch.isReloading
    for seam in layout.seams {
      seam.copyTexts = texts
      seam.copyButtonsAreEnabled = enabled
    }
  }

  /// What the buttons that copy to the file of `role`, in `direction`, are called.
  private func copyText(
    _ direction: PaneSeam.CopyDirection, to role: Role
  ) -> PaneSeam.CopyText {
    let name = presentation.headers[role]?.distinctName ?? role.letter
    let toolTip =
      direction == .toRight
      ? String(
        localized: "Copy to the right (⌥⌘→)", bundle: .module,
        comment: "Help tag of the arrow at the seam that copies a change to the right file.")
      : String(
        localized: "Copy to the left (⌥⌘←)", bundle: .module,
        comment: "Help tag of the arrow at the seam that copies a change to the left file.")
    let removalToolTip =
      direction == .toRight
      ? String(
        localized: "Remove these lines on the right (⌥⌘→)", bundle: .module,
        comment: "Help tag of the bin at the seam that removes the lines of a change on the right.")
      : String(
        localized: "Remove these lines on the left (⌥⌘←)", bundle: .module,
        comment: "Help tag of the bin at the seam that removes the lines of a change on the left.")
    let titleFormat =
      direction == .toRight
      ? String(
        localized: "Copy Change %lld to Right", bundle: .module,
        comment:
          "VoiceOver: the arrow at the seam that copies a change to the right file, such as Copy Change 3 to Right."
      )
      : String(
        localized: "Copy Change %lld to Left", bundle: .module,
        comment:
          "VoiceOver: the arrow at the seam that copies a change to the left file, such as Copy Change 3 to Left."
      )
    let removalTitleFormat =
      direction == .toRight
      ? String(
        localized: "Remove Change %lld from Right", bundle: .module,
        comment:
          "VoiceOver: the bin at the seam that removes the lines of a change from the right file, such as Remove Change 3 from Right."
      )
      : String(
        localized: "Remove Change %lld from Left", bundle: .module,
        comment:
          "VoiceOver: the bin at the seam that removes the lines of a change from the left file, such as Remove Change 3 from Left."
      )
    return PaneSeam.CopyText(
      titleFormat: titleFormat,
      help: String(
        localized: "Replaces the lines of \(name) with those of the other side.",
        bundle: .module,
        comment:
          "VoiceOver hint of the button at the seam that copies a change, such as to main.swift."),
      toolTip: toolTip, removalTitleFormat: removalTitleFormat,
      removalHelp: String(
        localized: "Removes these lines from \(name).", bundle: .module,
        comment:
          "VoiceOver hint of the bin at the seam, where the other side has no lines, such as from main.swift."
      ),
      removalToolTip: removalToolTip)
  }

  /// The name of the file that copying in `direction` writes to, as the context menu and the
  /// announcements say it.
  func copyTargetName(_ direction: PaneSeam.CopyDirection) -> String {
    let arrangement = presentation.arrangement
    let role = direction == .toRight ? arrangement.trailingRole : arrangement.leadingRole
    return presentation.headers[role]?.distinctName ?? role.letter
  }

  /// Carries out `command`, which copies changes, at `block`, or at every changed block for a
  /// command that copies all: the target takes the text of the other side, the files are
  /// compared anew away from the main actor while the window keeps showing the old comparison,
  /// and the copy becomes one step of undo named after the command.
  ///
  /// Afterwards the line of the side copied from stays at the reading line, the runs expanded
  /// stay so, and so does the one where the copy was, and the next change becomes current as
  /// Go to Next Change After Choosing says. VoiceOver hears where the text went and how many
  /// changes are left.
  ///
  /// - Returns: The task of the copy, which ends once the window shows its outcome, or `nil` if
  ///   the command has no effect.
  @discardableResult
  func copy(_ command: SessionCommand, block: Int?) -> Task<Void, Never>? {
    guard let (direction, allChanges) = command.copy,
      canCopy(direction, block: block, allChanges: allChanges)
    else { return nil }
    return Task {
      // Another copy may have begun since, or the comparison changed; the copy acts on what the
      // window shows as it begins.
      guard canCopy(direction, block: block, allChanges: allChanges) else { return }
      await copy(command, in: direction, block: allChanges ? nil : block)
    }
  }

  /// Carries out the copy of `command` in `direction`, of `block` or of every changed block for
  /// `nil`, as the one comparison under way.
  private func copy(
    _ command: SessionCommand, in direction: PaneSeam.CopyDirection, block: Int?
  ) async {
    let changes = presentation.changes
    let arrangement = presentation.arrangement
    let source = direction == .toRight ? arrangement.leadingRole : arrangement.trailingRole
    let copied = block.map { changes.blocks[$0] }
    let copy =
      copied.map { ChangeCopy(block: $0, from: source) } ?? ChangeCopy(allChangesFrom: source)
    let place = copied?.lines(in: source)
    let targetName = copyTargetName(direction)
    let expandedLines = presentation.collapsed.expandedRuns.map {
      presentation.collapsed.lines(of: $0, in: source)
    }
    let collapsesUnchangedRows = presentation.collapsed.collapsesUnchangedRows
    let goesToNextChange = settings.goesToNextChange
    await comparisonSwitcher.whileComparingAnew {
      let session: Session
      do throws(MergeModelError) {
        session = try await changes.session.copying(copy)
      } catch {
        await copyFailed(error, to: targetName)
        return
      }
      let collapsed = await Self.collapsed(
        session, collapsingUnchangedRows: collapsesUnchangedRows,
        expanding: expandedLines + [place].compactMap(\.self), in: source)
      let prepared = await prepared(.comparison(session), collapsed: collapsed)
      let blocks = prepared.changes.blocks
      let (current, blockAfterPlace) = Self.currentBlock(
        after: place, of: source, among: blocks, goingOn: goesToNextChange)
      show(
        prepared, named: command.undoName ?? command.title,
        copy: CopyReturn(source: source, targetName: targetName, copiesAgain: false)
      ) {
        presentation.showCopied(
          prepared, keepingTheLineOf: source, current: current, before: blockAfterPlace)
      }
      // The change that became current comes into view if it is not, so that the next copy
      // never changes lines out of sight; one in view stays where it is.
      presentation.showCurrentBlock()
      presentation.announce(Self.copiedAnnouncement(to: targetName, leaving: blocks.count))
    }
  }

  /// The block to make current after a copy of the lines `place` of the input of `role`, or
  /// with none, the index of the first block after the place; `blocks` are the changed blocks
  /// after the copy.
  ///
  /// Going on, the next change after the place becomes current; without one, no block is, and
  /// the jumps go on from the place. Else what is left of the copied block at the place stays
  /// current, if anything is, and no block otherwise. After a copy of every change, no block is
  /// current.
  static func currentBlock(
    after place: Range<Int>?, of role: Role, among blocks: [Block], goingOn: Bool
  ) -> (current: Int?, blockAfterPlace: Int?) {
    guard let place else { return (nil, nil) }
    let next = blocks.firstIndex { $0.lines(in: role).lowerBound >= place.upperBound }
    if goingOn {
      return next.map { ($0, nil) } ?? (nil, blocks.count)
    }
    let left = blocks.firstIndex { block in
      let lines = block.lines(in: role)
      return lines.overlaps(place) || lines.lowerBound == place.lowerBound
    }
    return left.map { ($0, nil) } ?? (nil, next ?? blocks.count)
  }

  /// The runs of unchanged rows of `session`, collapsed as `collapsingUnchangedRows` says, with
  /// those expanded that hold lines of `expanded`, lines of the input of `role`; worked out away
  /// from the main actor.
  @concurrent
  private static func collapsed(
    _ session: Session, collapsingUnchangedRows: Bool, expanding expanded: [Range<Int>],
    in role: Role
  ) async -> CollapsedRows {
    var collapsed = CollapsedRows(session: session, collapsesUnchangedRows: collapsingUnchangedRows)
    let lineCount = session.rowLayout.lineCount(in: role)
    guard lineCount > 0 else { return collapsed }
    for lines in expanded {
      for line in [lines.lowerBound, max(lines.upperBound - 1, lines.lowerBound)] {
        collapsed.expandToShow(line: min(line, lineCount - 1), in: role)
      }
    }
    return collapsed
  }

  /// Tells that the copy to `name` failed, and keeps the comparison shown now.
  private func copyFailed(_ error: MergeModelError, to name: String) async {
    guard let window else { return }
    guard case .unrepresentableText(let encoding) = error else {
      await comparisonFailed(error)
      return
    }
    await prompts.reportUnrepresentableCopy(to: name, in: encoding, in: window)
  }

  /// What VoiceOver hears after a copy to `name`, which leaves `count` changes.
  static func copiedAnnouncement(to name: String, leaving count: Int) -> String {
    let changes = SessionToolbar.countText(currentChange: nil, changeCount: count)
    return String(
      localized: "Copied to \(name). \(changes)", bundle: .module,
      comment: "VoiceOver after copying a change, such as Copied to main.swift. 11 Changes.")
  }

  /// What VoiceOver hears after undo takes back a copy.
  static var restoredAnnouncement: String {
    String(
      localized: "Change restored", bundle: .module,
      comment: "VoiceOver after undo took back the copy of a change.")
  }
}

extension SessionWindowController: PaneSeamDelegate {
  /// Copies `block` as Copy to Right or Copy to Left would if it were current; the click does
  /// not make it current first.
  func seam(_ seam: PaneSeam, didAskToCopyBlock block: Int, in direction: PaneSeam.CopyDirection) {
    copying = copy(.copy(direction), block: block)
  }
}
