import MergeModel
import PaneKit
import SwiftUI
import TextBasics

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
      SideNamesView(header: header, theme: theme)
      Spacer(minLength: 0)
      SideDetailsButton(header: header) { showsDetails = true }
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

/// What a header says about a side: its badge, its real name and role, and its line endings and
/// encoding where they differ from the other sides.
struct SideNamesView: View {
  let header: SideHeader
  let theme: Theme

  var body: some View {
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
    if let lineEndingStyle = header.differingLineEndingStyle {
      Text(lineEndingStyle.name)
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
  }
}

/// The quiet button ⓘ of a header, which opens the details of its side, so that the keyboard and
/// VoiceOver reach them too.
struct SideDetailsButton: View {
  let header: SideHeader
  let action: () -> Void

  var body: some View {
    Button(action: action) {
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
}

/// The letter of a side in a badge of its color, the color that a chosen toggle of the side
/// has: a clear yellow with a dark letter for the base.
struct SideBadge: View {
  let role: Role
  let theme: Theme

  var body: some View {
    Text(role.letter)
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color(nsColor: theme.chosenSignColor(for: role.colorRole)))
      .padding(.horizontal, WindowMetrics.badgePadding)
      .frame(minWidth: WindowMetrics.badgeHeight, minHeight: WindowMetrics.badgeHeight)
      .background(Capsule().fill(Color(nsColor: theme.chosenFill(for: role.colorRole))))
      .accessibilityHidden(true)
  }
}

extension LineEnding {
  /// The short name of the line ending, as editors show it.
  var name: String {
    switch self {
    case .lf: String(localized: "LF", bundle: .module, comment: "Line endings: line feed.")
    case .crlf:
      String(localized: "CRLF", bundle: .module, comment: "Line endings: CR LF.")
    case .cr: String(localized: "CR", bundle: .module, comment: "Line endings: carriage return.")
    }
  }
}

extension LineEndingStyle {
  /// The short name of the line endings, as editors show it.
  var name: String {
    switch self {
    case .uniform(let lineEnding): lineEnding.name
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
