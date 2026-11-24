import FolderCompare
import Foundation
import GitSupport
import MergeModel
import TextBasics

/// What the header above the pane of an input says: the letter of the side, its real name, its
/// role in the Git operation, and the details its popover shows.
struct SideHeader: Equatable {
  /// Where the role stands in the header.
  enum RolePlacement: Equatable {
    /// After the name, in the secondary color, as in an ordinary merge, where the sides lie as
    /// expected.
    case afterName
    /// Before the name, as prominent as the name, as in a rebase, a cherry-pick, a revert and a
    /// stash, where the sides lie otherwise than expected.
    case beforeName
  }

  /// The facts the popover of the header shows.
  struct Details: Equatable {
    /// The commit the side comes from, if it is known.
    var commit: CommitDetails?

    /// Where the file of the side was read from, or its label if it was not read from disk or
    /// holds text pasted from the clipboard.
    var location: String

    /// How the lines of the file end, if the file has line breaks.
    var lineEndingStyle: LineEndingStyle?

    /// The encoding the file was read in, if it is text.
    var encoding: FileEncoding?
  }

  /// The input the pane shows.
  let role: Role

  /// The real name of the side: a branch, a commit or the name of the file, on one line.
  ///
  /// A file name may hold line breaks and other control characters; they stand as spaces, so
  /// that the name fits wherever it is shown or written, such as in the preview of a conflict.
  let name: String

  /// The name that tells the side apart in a sentence, such as "main removed these lines":
  /// the name that Git or the command line gives the side, else the name of its file if the
  /// other side's file is named otherwise, else its letter.
  ///
  /// The sides of a merge that Git started often show the same file name, which tells them
  /// apart no more than nothing does.
  let distinctName: String

  /// The role of the side in the operation in words, such as "incoming", if it has one.
  let roleText: String?

  /// Where the role stands.
  let rolePlacement: RolePlacement

  /// How the lines of the file end, shown only where they differ from the other sides.
  let differingLineEndingStyle: LineEndingStyle?

  /// The encoding of the file, shown only where it differs from the other sides.
  let differingEncoding: FileEncoding?

  /// The facts for the popover.
  let details: Details

  /// Whether the file has copied changes that are not saved, which the header says quietly.
  var isEdited = false

  /// The headers of the panes of the inputs of `session` in `context`, by role.
  static func headers(of session: Session, context: SessionContext) -> [Role: SideHeader] {
    Dictionary(
      uniqueKeysWithValues: session.inputs.map { role, file in
        (role, SideHeader(role: role, file: file, session: session, context: context))
      })
  }

  /// The header of the pane of `role` in `session` and `context`, or `nil` if the input does not
  /// take part.
  static func header(
    of role: Role, in session: Session, context: SessionContext
  ) -> SideHeader? {
    session.inputs[role].map {
      SideHeader(role: role, file: $0, session: session, context: context)
    }
  }

  /// The header of the pane of `role`, whose file in `session` is `file`.
  ///
  /// The names come from Git where Git started the merge; otherwise, and for a side Git does not
  /// name, the label of the file stands in. A missing side of a comparison, `/dev/null` for a
  /// file that is new or deleted, is the new or the deleted file. Where both sides of a
  /// comparison have the same name, as the copies Git and Tower pass, the role tells them apart:
  /// the working copy, or else the earlier and the later version.
  private init(role: Role, file: SourceFile, session: Session, context: SessionContext) {
    let side = context.git.map { git in
      switch role {
      case .a: git.remote
      case .base: git.base
      case .b: git.local
      }
    }
    self.role = role
    name = Self.name(of: role, session: session, context: context)
    distinctName =
      side?.name == nil ? Self.distinctLabel(of: role, in: session) : name
    roleText =
      side?.role.map(Self.text(of:))
      ?? Self.comparisonRole(of: role, named: name, session: session, context: context)
    rolePlacement =
      switch context.git?.operation {
      case .merge, nil: .afterName
      case .rebase, .cherryPick, .revert, .stash: .beforeName
      }
    differingLineEndingStyle = session.lineEndingsDiffer ? file.lineEndingStyle : nil
    let encodings = Set(session.inputs.values.compactMap(\.encoding))
    differingEncoding = encodings.count > 1 ? file.encoding : nil
    details = Details(
      commit: side?.commit,
      location: file.url.flatMap { url in
        context.pastedTexts[url] == nil ? url.path(percentEncoded: false) : nil
      } ?? file.label,
      lineEndingStyle: file.lineEndingStyle, encoding: file.encoding)
  }

  /// The name of the side as a whole, for VoiceOver and the help tag: letter, role and name in
  /// the order the header shows them.
  var spokenName: String {
    guard isEdited else { return spokenSide }
    return String(
      localized: "\(spokenSide), \(Self.editedText)", bundle: .module,
      comment: "VoiceOver: a pane whose file has unsaved changes, such as B, main.swift, Edited.")
  }

  /// The letter, the role and the name of the side in the order the header shows them.
  private var spokenSide: String {
    guard let roleText else {
      return String(
        localized: "\(role.letter), \(name)", bundle: .module,
        comment: "VoiceOver: a pane, such as A, feature/login.")
    }
    let (first, second) = rolePlacement == .afterName ? (name, roleText) : (roleText, name)
    return String(
      localized: "\(role.letter), \(first), \(second)", bundle: .module,
      comment:
        "VoiceOver: a pane with its name and role in the order the header shows them, such as A, feature/login, incoming or A, your commit, 1a2b3c4 Fix typo."
    )
  }

  /// What the header of a file with unsaved changes says, as the title of a document does.
  static var editedText: String {
    String(
      localized: "Edited", bundle: .module,
      comment: "Header of a file whose copied changes are not saved yet.")
  }

  /// The name in the header of `role`: the name Git gives the side, the new or the deleted file
  /// for a missing side of a comparison, else the label of the file on one line.
  private static func name(of role: Role, session: Session, context: SessionContext) -> String {
    let side = context.git.map { git in
      switch role {
      case .a: git.remote
      case .base: git.base
      case .b: git.local
      }
    }
    if let name = side?.name {
      return singleLine(text(of: name))
    }
    let file = session.inputs[role]
    if session.kind == .diff, let url = file?.url, FileOrigin(url: url) == .missing {
      return role == .a
        ? String(
          localized: "New File", bundle: .module,
          comment: "Header of the missing earlier side of a comparison of a new file.")
        : String(
          localized: "Deleted File", bundle: .module,
          comment: "Header of the missing later side of a comparison of a deleted file.")
    }
    let label = file?.label ?? ""
    return singleLine(label.isEmpty ? role.letter : label)
  }

  /// What the side `role` of a comparison is, if its name `name` is also the name of the other
  /// side: the folder it comes from in a comparison of folders, the working copy, or else the
  /// earlier or the later version.
  private static func comparisonRole(
    of role: Role, named name: String, session: Session, context: SessionContext
  ) -> String? {
    guard session.kind == .diff, role != .base else { return nil }
    let other: Role = role == .a ? .b : .a
    guard Self.name(of: other, session: session, context: context) == name
    else { return nil }
    if let folders = context.folders {
      let names = folders.distinctNames
      return singleLine(role == .a ? names.left : names.right)
    }
    let diffRole =
      context.difftool.map { role == .a ? $0.leftRole : $0.rightRole }
      ?? (role == .a ? .before : .after)
    return text(of: diffRole)
  }

  /// The label of the file of `role` on one line, if no other side that a sentence sets it
  /// against has a file of the same label: B for A, A for B, both for the base; else the letter.
  private static func distinctLabel(of role: Role, in session: Session) -> String {
    let files = session.inputs
    let label = files[role]?.label ?? ""
    let others: [Role] =
      switch role {
      case .a: [.b]
      case .b: [.a]
      case .base: [.a, .b]
      }
    let isShared = others.contains { files[$0]?.label == label }
    return label.isEmpty || isShared ? role.letter : singleLine(label)
  }

  /// `text` with a space for every line break and every other control character.
  static func singleLine(_ text: String) -> String {
    String(
      String.UnicodeScalarView(
        text.unicodeScalars.map { scalar in
          switch scalar.properties.generalCategory {
          case .control, .lineSeparator, .paragraphSeparator: " "
          default: scalar
          }
        }))
  }

  /// A name of a side in words.
  static func text(of name: SideName) -> String {
    switch name {
    case .reference(let reference):
      return reference
    case .commit(let hash, let subject, let branch):
      let commit = subject.map { "\(hash) \($0)" } ?? hash
      return branch.map {
        String(
          localized: "\(commit) · \($0)", bundle: .module,
          comment: "The name of a commit followed by its branch, such as 1a2b3c4 Fix typo · main.")
      } ?? commit
    case .stash:
      return String(
        localized: "Stash", bundle: .module, comment: "The name of a stash in a header.")
    }
  }

  /// What a side of a comparison is, in words.
  static func text(of role: DiffSideRole) -> String {
    switch role {
    case .before:
      String(
        localized: "Earlier Version", bundle: .module,
        comment: "Role: the file before the change, shown when both sides have the same name.")
    case .after:
      String(
        localized: "Later Version", bundle: .module,
        comment: "Role: the file after the change, shown when both sides have the same name.")
    case .workingCopy:
      String(
        localized: "Working Copy", bundle: .module,
        comment: "Role: the file in the working tree, which the user can edit.")
    }
  }

  /// A role of a side in words.
  static func text(of role: SideRole) -> String {
    switch role {
    case .incoming:
      String(localized: "incoming", bundle: .module, comment: "Role: the branch being merged in.")
    case .yours:
      String(localized: "yours", bundle: .module, comment: "Role: the branch the user is on.")
    case .yourCommit:
      String(
        localized: "your commit", bundle: .module,
        comment: "Role: the user's own commit that a rebase moves.")
    case .rebaseTarget:
      String(
        localized: "rebase target", bundle: .module,
        comment: "Role: the commit a rebase moves the user's commits onto.")
    case .cherryPickedCommit:
      String(
        localized: "cherry-picked commit", bundle: .module,
        comment: "Role: the commit being cherry-picked.")
    case .revertedCommit:
      String(
        localized: "reverted commit", bundle: .module, comment: "Role: the commit being reverted.")
    }
  }
}
