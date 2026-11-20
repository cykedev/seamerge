import FolderCompare
import Foundation
import GitSupport
import MergeModel
import SeamergeUI
import SessionIPC

// The request carries values of its own, so that the helper and the app share no more than the
// protocol. These initializers carry over what the helper found out about a merge or a
// comparison, field by field, into the values the window shows.

extension GitContext {
  /// What the helper found out about a merge; `hasCommonAncestor` tells whether it sent a base.
  init(_ context: SessionRequest.MergeContext, hasCommonAncestor: Bool) {
    self.init(
      operation: context.operation.map(GitOperation.init),
      remote: MergeSide(context.remote),
      local: MergeSide(context.local),
      base: MergeSide(context.base),
      hasCommonAncestor: hasCommonAncestor,
      rebaseProgress: context.rebaseProgress.map(RebaseProgress.init),
      remainingConflictedFileCount: context.remainingConflictedFileCount)
  }
}

extension DifftoolContext {
  /// What the helper found out about a comparison through `git difftool`, or `nil` if the
  /// comparison has no path in the repository, as one Git did not start.
  init?(_ diff: SessionRequest.Diff) {
    guard let path = diff.displayPath else { return nil }
    self.init(
      path: path, leftRole: DiffSideRole(diff.context.leftRole),
      rightRole: DiffSideRole(diff.context.rightRole),
      filePosition: diff.context.filePosition.map {
        FilePosition(number: $0.number, count: $0.count)
      })
  }
}

extension DiffSideRole {
  init(_ role: SessionRequest.DiffSideRole) {
    self =
      switch role {
      case .before: .before
      case .after: .after
      case .workingCopy: .workingCopy
      }
  }
}

extension GitOperation {
  init(_ operation: SessionRequest.GitOperation) {
    self =
      switch operation {
      case .merge: .merge
      case .rebase: .rebase
      case .cherryPick: .cherryPick
      case .revert: .revert
      case .stash: .stash
      }
  }
}

extension MergeSide {
  init(_ side: SessionRequest.Side) {
    self.init(
      name: side.name.map(SideName.init), role: side.role.map(SideRole.init),
      commit: side.commit.map(CommitDetails.init))
  }
}

extension SideName {
  init(_ name: SessionRequest.SideName) {
    self =
      switch name {
      case .reference(let reference): .reference(reference)
      case .commit(let abbreviatedHash, let subject, let branch):
        .commit(abbreviatedHash: abbreviatedHash, subject: subject, branch: branch)
      case .stash: .stash
      }
  }
}

extension SideRole {
  init(_ role: SessionRequest.SideRole) {
    self =
      switch role {
      case .incoming: .incoming
      case .yours: .yours
      case .yourCommit: .yourCommit
      case .rebaseTarget: .rebaseTarget
      case .cherryPickedCommit: .cherryPickedCommit
      case .revertedCommit: .revertedCommit
      }
  }
}

extension CommitDetails {
  init(_ commit: SessionRequest.Commit) {
    self.init(
      hash: commit.hash, abbreviatedHash: commit.abbreviatedHash, authorName: commit.authorName,
      authorDate: commit.authorDate, subject: commit.subject)
  }
}

extension RebaseProgress {
  init(_ progress: SessionRequest.RebaseProgress) {
    self.init(
      targetName: SideName(progress.targetName), commitNumber: progress.commitNumber,
      commitCount: progress.commitCount)
  }
}

extension CollectionOrigin {
  /// The origin the helper sent with a comparison.
  init(_ origin: SessionRequest.Origin) {
    self.init(
      repository: origin.repository,
      run: origin.run.map { ProcessRun(processID: $0.processID, startTime: $0.startTime) })
  }
}

extension CollectedFile {
  /// The files of a comparison the helper sent, named as a comparison that Git started.
  init(_ diff: SessionRequest.Diff) {
    let path = diff.displayPath ?? diff.right.lastPathComponent
    self.init(
      old: SessionFile(url: diff.left, label: diff.leftLabel ?? path),
      new: SessionFile(url: diff.right, label: diff.rightLabel ?? path),
      difftool: DifftoolContext(diff) ?? DifftoolContext(path: path))
  }
}
