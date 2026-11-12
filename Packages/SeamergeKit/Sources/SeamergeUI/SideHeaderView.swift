import MergeModel
import PaneKit
import SwiftUI

/// The header above the pane of an input: the badge of the side, its real name and role, and a
/// quiet button for its details.
///
/// A click anywhere on the header opens the details as well; the button is there so that the
/// keyboard and VoiceOver reach them too.
struct SideHeaderView: View {
  let header: SideHeader
  let theme: Theme

  @State private var showsDetails = false

  var body: some View {
    HStack(spacing: WindowMetrics.headerSpacing) {
      SideBadge(role: header.role, theme: theme)
      if let roleText = header.roleText, header.rolePlacement == .beforeName {
        Text(roleText)
          .font(.subheadline)
          .layoutPriority(1)
      }
      Text(header.name)
        .font(.headline)
        .truncationMode(.middle)
      if let roleText = header.roleText, header.rolePlacement == .afterName {
        Text(roleText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if let lineEndings = header.differingLineEndings {
        Text(lineEndings.name)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .help(
            Text(
              "Differs from the line endings of the other files",
              bundle: .module,
              comment: "Help tag of the line endings in a header, shown only where they differ."))
      }
      if let encoding = header.differingEncoding {
        Text(encoding.name)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .help(
            Text(
              "Differs from the encoding of the other files", bundle: .module,
              comment: "Help tag of the encoding in a header, shown only where it differs."))
      }
      Spacer(minLength: 0)
      Button {
        showsDetails = true
      } label: {
        Image(systemName: "info.circle")
          .frame(width: WindowMetrics.minimumHitTarget, height: WindowMetrics.minimumHitTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help(Text("Show where this side comes from", bundle: .module, comment: "Help tag of ⓘ."))
      .accessibilityLabel(
        Text(
          "Details about \(header.spokenName)", bundle: .module,
          comment: "VoiceOver: the ⓘ of a header, such as Details about A, main."
        ))
    }
    .lineLimit(1)
    .padding(.horizontal, WindowMetrics.headerInset)
    .frame(height: WindowMetrics.headerHeight)
    .contentShape(Rectangle())
    .onTapGesture { showsDetails = true }
    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
      SideDetailsView(header: header, theme: theme)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(header.spokenName))
  }
}

/// The letter of a side in a badge of its color.
struct SideBadge: View {
  let role: Role
  let theme: Theme

  var body: some View {
    Text(role.letter)
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color(nsColor: theme.filledLabelColor))
      .padding(.horizontal, WindowMetrics.badgePadding)
      .frame(minWidth: WindowMetrics.badgeHeight, minHeight: WindowMetrics.badgeHeight)
      .background(Capsule().fill(Color(nsColor: theme.symbolColor(for: role.colorRole))))
      .accessibilityHidden(true)
  }
}

extension LineEndings {
  /// The short name of the line endings, as editors show it.
  var name: String {
    switch self {
    case .lf: String(localized: "LF", bundle: .module, comment: "Line endings: line feed.")
    case .crlf:
      String(localized: "CRLF", bundle: .module, comment: "Line endings: CR LF.")
    case .cr: String(localized: "CR", bundle: .module, comment: "Line endings: carriage return.")
    case .mixed:
      String(localized: "Mixed", bundle: .module, comment: "Line endings: more than one kind.")
    }
  }
}

extension FileEncoding {
  /// The name of the encoding, as editors show it.
  var name: String {
    switch self {
    case .utf8: String(localized: "UTF-8", bundle: .module, comment: "Encoding.")
    case .utf16LittleEndian:
      String(localized: "UTF-16 LE", bundle: .module, comment: "Encoding: UTF-16 little-endian.")
    case .utf16BigEndian:
      String(localized: "UTF-16 BE", bundle: .module, comment: "Encoding: UTF-16 big-endian.")
    case .utf32LittleEndian:
      String(localized: "UTF-32 LE", bundle: .module, comment: "Encoding: UTF-32 little-endian.")
    case .utf32BigEndian:
      String(localized: "UTF-32 BE", bundle: .module, comment: "Encoding: UTF-32 big-endian.")
    case .windows1252:
      String(localized: "Windows 1252", bundle: .module, comment: "Encoding: Windows code page.")
    case .isoLatin1:
      String(localized: "ISO 8859-1", bundle: .module, comment: "Encoding: ISO Latin 1.")
    case .macRoman: String(localized: "Mac Roman", bundle: .module, comment: "Encoding.")
    }
  }
}
