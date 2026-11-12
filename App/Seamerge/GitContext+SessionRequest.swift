import GitSupport
import SessionIPC

// The request carries values of its own, so that the helper and the app share no more than the
// protocol. These initializers carry over what the helper found out, field by field, into the
// values the window shows.

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
