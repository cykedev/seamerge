import MergeModel
import SwiftUI

/// What the header above the result says: where the result goes, the encoding and line endings
/// it is written with, and whether B mixes line endings, which the result does not.
struct ResultHeader: Equatable {
  /// Where the result is written, with the home folder as a tilde, if it goes to a file.
  var path: String?

  /// How the result is written, or `nil` while it is not known, as before the files of a merge
  /// are compared.
  var format: ResultFormat?

  /// The name of B if it ends its lines in more than one way, so that writing the result
  /// unifies them; `nil` otherwise.
  var bWithMixedLineEndings: String?

  /// Whether Git waits for the merge, so that the line after it stopped waiting names Git.
  let callerIsGit: Bool

  /// The header of the result of `session` in `context`, written as B is.
  init(session: Session, context: SessionContext) {
    path = context.resultURL.map(Self.path(of:))
    format = ResultFormat(resultOf: session)
    bWithMixedLineEndings =
      session.file(for: .b)?.lineEndingStyle?.isMixed == true
      ? SideHeader(role: .b, session: session, context: context).distinctName : nil
    callerIsGit = context.waitingCaller == .git
  }

  /// `url` as the header shows it, with the home folder as a tilde.
  static func path(of url: URL) -> String {
    (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
  }

  /// The name of the result pane for VoiceOver.
  var spokenName: String {
    guard let path else {
      return String(localized: "Result", bundle: .module, comment: "The name of the result pane.")
    }
    return String(
      localized: "Result, \(path)", bundle: .module,
      comment: "VoiceOver: the result pane and the file it is written to.")
  }
}

/// The header above the result, with the pop-up menus of the encoding and the line endings; below
/// it, while B mixes line endings, a line that says the result unifies them, and while Git no
/// longer waits for the merge, a line that says so.
struct ResultHeaderView: View {
  let header: ResultHeader
  let callerIsGone: Bool

  /// Carries out a choice of the pop-up menus, as the items of the File menu do.
  let choose: (ResultFormatChoice) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: WindowMetrics.headerSpacing) {
        Text("Result", bundle: .module, comment: "The name of the result pane.")
          .font(.headline)
        if let path = header.path {
          Text(path)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .truncationMode(.middle)
        }
        Spacer(minLength: 0)
        if let format = header.format {
          menu(
            of: ResultFormatChoice.encodings, current: .encoding(format.encoding),
            label: ResultFormatChoice.encodingMenuTitle, help: ResultFormatChoice.encodingHelp)
          menu(
            of: ResultFormatChoice.lineEndings, current: .lineEnding(format.lineEnding),
            label: ResultFormatChoice.lineEndingMenuTitle,
            help: ResultFormatChoice.lineEndingHelp)
        }
      }
      .frame(height: WindowMetrics.headerHeight)
      if let b = header.bWithMixedLineEndings, let format = header.format {
        notice(
          Text(
            "\(b) mixes line endings. The result is written with \(ResultFormatChoice.lineEnding(format.lineEnding).title) throughout.",
            bundle: .module,
            comment:
              "Notice below the result header: B ends its lines in more than one way, such as main mixes line endings. The result is written with LF throughout."
          ))
      }
      if callerIsGone {
        notice(
          header.callerIsGit
            ? Text(
              "Git is no longer waiting for this merge.", bundle: .module,
              comment: "Notice below the result header after the Git command that asked has ended.")
            : Text(
              "The command that opened this merge is no longer waiting.", bundle: .module,
              comment:
                "Notice below the result header after a command other than Git that asked has ended."
            ))
      }
    }
    .lineLimit(1)
    .padding(.horizontal, WindowMetrics.headerInset)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(header.spokenName))
  }

  /// A quiet pop-up menu of `choices`, titled with the current one, which has a checkmark.
  private func menu(
    of choices: [ResultFormatChoice], current: ResultFormatChoice, label: String, help: String
  ) -> some View {
    Menu {
      ForEach(choices, id: \.self) { choice in
        Toggle(
          isOn: Binding(get: { choice == current }, set: { _ in choose(choice) })
        ) {
          Text(choice.title)
        }
      }
    } label: {
      HStack(spacing: WindowMetrics.menuIndicatorSpacing) {
        Text(current.title)
        Image(systemName: "chevron.down")
          .imageScale(.small)
          .fontWeight(.semibold)
      }
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .font(.subheadline)
    .help(help)
    .accessibilityLabel(Text(label))
    .accessibilityValue(Text(current.title))
  }

  private func notice(_ text: Text) -> some View {
    Label {
      text
    } icon: {
      Image(systemName: "exclamationmark.triangle")
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .frame(height: WindowMetrics.noticeHeight)
  }
}
