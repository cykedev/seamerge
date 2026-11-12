import GitSupport
import SessionIPC

// The request carries values of its own, so that the app reads it without GitSupport. These
// initializers carry over what GitSupport found out, field by field.

extension SessionRequest.MergeContext {
  /// The context of a merge as GitSupport detected it.
  init(_ context: GitContext) {
    self.init(
      operation: context.operation.map(SessionRequest.GitOperation.init),
      remote: SessionRequest.Side(context.remote),
      local: SessionRequest.Side(context.local),
      base: SessionRequest.Side(context.base),
      rebaseProgress: context.rebaseProgress.map(SessionRequest.RebaseProgress.init),
      remainingConflictedFileCount: context.remainingConflictedFileCount)
  }
}

extension SessionRequest.GitOperation {
  init(_ operation: GitOperation) {
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

extension SessionRequest.Side {
  init(_ side: MergeSide) {
    self.init(
      name: side.name.map(SessionRequest.SideName.init),
      role: side.role.map(SessionRequest.SideRole.init),
      commit: side.commit.map(SessionRequest.Commit.init))
  }
}

extension SessionRequest.SideName {
  init(_ name: SideName) {
    self =
      switch name {
      case .reference(let reference): .reference(reference)
      case .commit(let abbreviatedHash, let subject, let branch):
        .commit(abbreviatedHash: abbreviatedHash, subject: subject, branch: branch)
      case .stash: .stash
      }
  }
}

extension SessionRequest.SideRole {
  init(_ role: SideRole) {
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

extension SessionRequest.Commit {
  init(_ commit: CommitDetails) {
    self.init(
      hash: commit.hash,
      abbreviatedHash: commit.abbreviatedHash,
      subject: commit.subject,
      authorName: commit.authorName,
      authorDate: commit.authorDate)
  }
}

extension SessionRequest.RebaseProgress {
  init(_ progress: RebaseProgress) {
    self.init(
      targetName: SessionRequest.SideName(progress.targetName),
      commitNumber: progress.commitNumber,
      commitCount: progress.commitCount)
  }
}

extension SessionRequest.DiffContext {
  /// The context of a comparison as GitSupport detected it.
  init(_ context: DifftoolContext) {
    self.init(
      leftRole: SessionRequest.DiffSideRole(context.leftRole),
      rightRole: SessionRequest.DiffSideRole(context.rightRole),
      filePosition: context.filePosition.map {
        SessionRequest.FilePosition(number: $0.number, count: $0.count)
      })
  }
}

extension SessionRequest.DiffSideRole {
  init(_ role: DiffSideRole) {
    self =
      switch role {
      case .before: .before
      case .after: .after
      case .workingCopy: .workingCopy
      }
  }
}
