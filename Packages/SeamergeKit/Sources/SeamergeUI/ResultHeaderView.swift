import MergeModel
import SwiftUI

/// What the header above the result says: where the result goes and how its lines end.
struct ResultHeader: Equatable {
  /// Where the result is written, with the home folder as a tilde, if it goes to a file.
  let path: String?

  /// How the lines of the result end: like those of B, or of the first other input that has
  /// line breaks.
  let lineEndings: LineEndings?

  /// The header of the result of `session` in `context`.
  init(session: Session, context: SessionContext) {
    path = context.resultURL.map {
      ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
    lineEndings = [Role.b, .a, .base].lazy.compactMap { session.file(for: $0)?.lineEndings }.first
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

/// The header above the result, and below it, while Git no longer waits for the merge, a line
/// that says so.
struct ResultHeaderView: View {
  let header: ResultHeader
  let callerIsGone: Bool

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
        if let lineEndings = header.lineEndings {
          Text(lineEndings.name)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
              Text(
                "Line endings: \(lineEndings.name)", bundle: .module,
                comment: "VoiceOver: the line endings of the result, such as Line endings: LF."))
        }
      }
      .frame(height: WindowMetrics.headerHeight)
      if callerIsGone {
        Label {
          Text(
            "Git is no longer waiting for this merge.", bundle: .module,
            comment: "Notice below the result header after the Git command that asked has ended.")
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(height: WindowMetrics.noticeHeight)
      }
    }
    .lineLimit(1)
    .padding(.horizontal, WindowMetrics.headerInset)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(header.spokenName))
  }
}
