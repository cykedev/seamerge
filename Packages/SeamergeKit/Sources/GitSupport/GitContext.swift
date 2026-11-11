import Foundation
import os

/// What Git is doing when it asks the tool to merge a file: the operation, the three sides and the
/// progress of the operation.
///
/// The sides follow `git mergetool`: ``remote`` is `REMOTE`, shown on the left as A, and
/// ``local`` is `LOCAL`, shown on the right as B. In a rebase, `LOCAL` is the commit the rebase
/// builds on and `REMOTE` is the user's own commit, the reverse of a merge; the roles say so.
public struct GitContext: Sendable, Hashable {
  private static let logger = Logger(subsystem: "app.eiden.seamerge", category: "GitSupport")

  /// The operation in progress, or `nil` if none is recognized.
  public var operation: GitOperation?

  /// The side Git calls `REMOTE`: the incoming changes, or the user's commit in a rebase.
  public var remote: MergeSide

  /// The side Git calls `LOCAL`: the branch the user is on, or the target of a rebase.
  ///
  /// In a rebase, the name is that of the target, but ``MergeSide/commit`` is `HEAD`: the target
  /// with the commits already applied, which is what `LOCAL` holds. Its subject is not the
  /// subject of the target.
  public var local: MergeSide

  /// The common ancestor of both sides.
  ///
  /// The base never has a role.
  public var base: MergeSide

  /// How far the rebase has come, if a rebase is in progress and its state can be read.
  public var rebaseProgress: RebaseProgress?

  /// How many files besides the merged one still have conflicts, or `nil` if Git cannot tell.
  public var remainingConflictedFileCount: Int?

  /// Finds out what Git is doing, from the conflict markers in the merged file and from the state
  /// of the repository.
  ///
  /// For each side, the first source that names it wins:
  /// 1. The labels of the first conflict in `mergedFile`. The label `HEAD` and the labels Git
  ///    makes up for a stash do not count; neither does a label naming a commit the repository
  ///    names with more detail, such as the commit being rebased together with its branch.
  /// 2. The state of the repository: the branch, the commit being applied, or a name for the
  ///    commit being merged.
  /// 3. Nothing: the side has no name.
  ///
  /// Each query has the time limit of `git`. A query that fails or takes too long leaves out only
  /// the fact it was asked for, so this never fails; outside a repository, only the labels of the
  /// conflict markers remain.
  ///
  /// - Parameters:
  ///   - workingDirectory: A directory in the working tree, usually the one Git starts the tool in.
  ///   - mergedFile: The file with the conflict markers, which Git passes as `MERGED`.
  ///   - git: Runs `git`.
  public static func detect(
    workingDirectory: URL, mergedFile: URL, git: Git = Git()
  ) -> GitContext {
    var labels: ConflictMarkerLabels?
    do {
      labels = try ConflictMarkers.labels(inContentsOf: mergedFile)
    } catch {
      logger.error("Cannot read the conflict markers: \(String(describing: error))")
    }
    let repository = Repository(git: git, workingDirectory: workingDirectory)
    let detection = Detection(repository: repository, labels: labels)
    return GitContext(
      operation: detection.operation,
      remote: detection.remote(),
      local: detection.local(),
      base: detection.base(),
      rebaseProgress: detection.rebaseProgress(),
      remainingConflictedFileCount: detection.remainingConflictedFileCount(besides: mergedFile))
  }
}

/// The work of ``GitContext/detect(workingDirectory:mergedFile:git:)``, which asks the repository
/// only for what the conflict markers leave open.
private struct Detection {
  let repository: Repository?
  let labels: ConflictMarkerLabels?
  let operation: GitOperation?

  /// The name of the commit a rebase moves the commits onto; `nil` unless a rebase is in progress.
  private let targetName: SideName?

  init(repository: Repository?, labels: ConflictMarkerLabels?) {
    self.repository = repository
    self.labels = labels
    if let operation = repository?.operation {
      self.operation = operation
    } else if labels?.local == "Updated upstream" && labels?.remote == "Stashed changes" {
      self.operation = .stash
    } else {
      self.operation = nil
    }
    targetName = operation == .rebase ? repository.flatMap(Self.rebaseTargetName) : nil
  }

  func remote() -> MergeSide {
    if operation == .stash { return MergeSide(name: .stash) }
    guard let repository, let operation else {
      return MergeSide(name: labels?.remote.map(Self.name(ofLabel:)))
    }
    let commit = remoteCommitHash(in: repository).flatMap(repository.commitDetails)
    let name =
      Self.name(fromLabel: labels?.remote, describing: commit)
      ?? commit.map { remoteName(of: $0, in: repository) }
    return MergeSide(name: name, role: Self.remoteRole(in: operation), commit: commit)
  }

  func local() -> MergeSide {
    guard let operation else {
      // Commands such as `git am -3` and `git checkout -m` leave no state to recognize, but their
      // label `HEAD` still stands for the current branch.
      let name =
        Self.name(fromLabel: labels?.local, describing: nil)
        ?? repository?.currentBranch.map(SideName.reference)
        ?? labels?.local.map(Self.name(ofLabel:))
      return MergeSide(name: name)
    }
    guard let repository else {
      // The label Git gives the local side of a stash names no branch.
      return MergeSide()
    }
    let commit = repository.commitDetails("HEAD")
    let labelName = operation == .stash ? nil : Self.name(fromLabel: labels?.local, describing: nil)
    let role: SideRole?
    let stateName: SideName?
    switch operation {
    case .rebase:
      role = .rebaseTarget
      stateName = targetName
    case .merge, .cherryPick:
      role = .yours
      stateName = repository.currentBranch.map(SideName.reference)
    case .revert, .stash:
      role = nil
      stateName = repository.currentBranch.map(SideName.reference)
    }
    let name = labelName ?? stateName ?? commit.map { Self.name(of: $0) }
    return MergeSide(name: name, role: role, commit: commit)
  }

  func base() -> MergeSide {
    if operation == .merge, let repository,
      let incoming = repository.commitHash(in: "MERGE_HEAD"),
      let hash = repository.mergeBase("HEAD", incoming),
      let commit = repository.commitDetails(hash)
    {
      let name = SideName.commit(abbreviatedHash: commit.abbreviatedHash, subject: nil, branch: nil)
      return MergeSide(name: name, commit: commit)
    }
    return MergeSide(name: labels?.base.map(Self.name(ofLabel:)))
  }

  func rebaseProgress() -> RebaseProgress? {
    guard let repository, let targetName else { return nil }
    let counters = [
      ("rebase-merge/msgnum", "rebase-merge/end"), ("rebase-apply/next", "rebase-apply/last"),
    ]
    for (numberFile, countFile) in counters {
      if let number = repository.number(in: numberFile),
        let count = repository.number(in: countFile), (1...count).contains(number)
      {
        return RebaseProgress(targetName: targetName, commitNumber: number, commitCount: count)
      }
    }
    return nil
  }

  func remainingConflictedFileCount(besides mergedFile: URL) -> Int? {
    guard let repository, let paths = repository.conflictedPaths else { return nil }
    guard let topLevel = repository.topLevel else { return paths.count }
    let topPath = Self.comparablePath(of: topLevel)
    let filePath = Self.comparablePath(of: mergedFile)
    guard filePath.hasPrefix(topPath + "/") else { return paths.count }
    let relativePath = String(filePath.dropFirst(topPath.count + 1))
    // Strings compare and hash by canonical equivalence, so a name the file system keeps
    // decomposed still matches the precomposed one Git lists.
    return paths.subtracting([relativePath]).count
  }

  private static func comparablePath(of url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  /// The hash of the commit the remote side comes from.
  private func remoteCommitHash(in repository: Repository) -> String? {
    switch operation {
    case .merge: repository.commitHash(in: "MERGE_HEAD")
    case .rebase:
      repository.commitHash(in: "rebase-merge/stopped-sha")
        ?? repository.commitHash(in: "REBASE_HEAD")
    case .cherryPick: repository.commitHash(in: "CHERRY_PICK_HEAD")
    case .revert: repository.commitHash(in: "REVERT_HEAD")
    case .stash, nil: nil
    }
  }

  /// The name the repository gives the commit of the remote side.
  private func remoteName(of commit: CommitDetails, in repository: Repository) -> SideName {
    switch operation {
    case .merge:
      return repository.name(ofCommit: commit.hash).map(SideName.reference) ?? Self.name(of: commit)
    case .rebase:
      let headName =
        repository.firstLine(of: "rebase-merge/head-name")
        ?? repository.firstLine(of: "rebase-apply/head-name")
      return Self.name(of: commit, branch: headName.flatMap(Self.branchName))
    case .cherryPick, .revert, .stash, nil:
      return Self.name(of: commit)
    }
  }

  private static func remoteRole(in operation: GitOperation) -> SideRole? {
    switch operation {
    case .merge: .incoming
    case .rebase: .yourCommit
    case .cherryPick: .cherryPickedCommit
    case .revert: .revertedCommit
    case .stash: nil
    }
  }

  private static func rebaseTargetName(in repository: Repository) -> SideName? {
    guard
      let hash = repository.commitHash(in: "rebase-merge/onto")
        ?? repository.commitHash(in: "rebase-apply/onto")
    else { return nil }
    return repository.name(ofCommit: hash).map(SideName.reference)
      ?? repository.commitDetails(hash).map { name(of: $0) }
  }

  /// The name a marker label gives a side, or `nil` if the label does not count.
  ///
  /// `HEAD` does not count, nor a label naming `commit`, which the repository describes better:
  /// Git's form `<hash> (<subject>)` or `parent of <hash> (<subject>)`, or the subject alone, as
  /// the older rebase backend writes it.
  private static func name(
    fromLabel label: String?, describing commit: CommitDetails?
  ) -> SideName? {
    guard let label, label != "HEAD" else { return nil }
    if let commit {
      if label == commit.subject { return nil }
      if let labelled = CommitLabel(label), commit.hash.hasPrefix(labelled.abbreviatedHash) {
        return nil
      }
    }
    return name(ofLabel: label)
  }

  /// The name for a marker label, with Git's form `<hash> (<subject>)` read as a commit.
  private static func name(ofLabel label: String) -> SideName {
    if let commit = CommitLabel(label), !commit.isParent {
      return .commit(abbreviatedHash: commit.abbreviatedHash, subject: commit.subject, branch: nil)
    }
    return .reference(label)
  }

  private static func name(of commit: CommitDetails, branch: String? = nil) -> SideName {
    .commit(abbreviatedHash: commit.abbreviatedHash, subject: commit.subject, branch: branch)
  }

  /// The short name of a branch from its full reference, such as in `rebase-merge/head-name`.
  private static func branchName(_ reference: String) -> String? {
    reference.hasPrefix("refs/heads/") ? String(reference.dropFirst("refs/heads/".count)) : nil
  }
}

/// A label in the form Git gives a commit in conflict markers: `<hash> (<subject>)`, or
/// `parent of <hash> (<subject>)` for the parent of that commit.
private struct CommitLabel {
  var abbreviatedHash: String
  var subject: String
  var isParent: Bool

  init?(_ label: String) {
    let pattern = /^(parent of )?([0-9a-f]{4,64}) \((.*)\)$/
    guard let match = label.wholeMatch(of: pattern) else { return nil }
    isParent = match.1 != nil
    abbreviatedHash = String(match.2)
    subject = String(match.3)
  }
}
