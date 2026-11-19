import GitSupport
import PaneKit
import SwiftUI

/// The details of a side in the popover of its header: the commit it comes from, its author and
/// date, where the file was read from, its encoding, and how its lines end.
struct SideDetailsView: View {
  let header: SideHeader
  let theme: Theme

  var body: some View {
    VStack(alignment: .leading, spacing: WindowMetrics.detailsSpacing) {
      HStack(spacing: WindowMetrics.headerSpacing) {
        SideBadge(role: header.role, theme: theme)
        Text(header.name).font(.headline)
        if let roleText = header.roleText {
          Text(roleText).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Grid(
        alignment: .leadingFirstTextBaseline, horizontalSpacing: WindowMetrics.headerSpacing,
        verticalSpacing: WindowMetrics.detailsRowSpacing
      ) {
        if let commit = header.details.commit {
          row(
            Text("Commit", bundle: .module, comment: "Details of a side: the commit."),
            value: "\(commit.abbreviatedHash) \(commit.subject)")
          row(
            Text(
              "Author", bundle: .module, comment: "Details of a side: the author of the commit."),
            value: commit.authorName)
          row(
            Text("Date", bundle: .module, comment: "Details of a side: when the commit was made."),
            value: commit.authorDate.formatted(date: .abbreviated, time: .shortened))
        }
        row(
          Text(
            "File", bundle: .module, comment: "Details of a side: where the file was read from."),
          value: header.details.location)
        if let encoding = header.details.encoding {
          row(
            Text("Encoding", bundle: .module, comment: "Details of a side: UTF-8 and the like."),
            value: encoding.name)
        }
        if let lineEndingStyle = header.details.lineEndingStyle {
          row(
            Text(
              "Line Endings", bundle: .module,
              comment:
                "Line endings: the label in the details of a side, LF, CRLF or CR, and the submenu of the File menu that chooses those of the result."
            ),
            value: lineEndingStyle.name)
        }
      }
    }
    .padding(WindowMetrics.detailsInset)
    .frame(maxWidth: WindowMetrics.detailsMaximumWidth, alignment: .leading)
  }

  private func row(_ label: Text, value: String) -> some View {
    GridRow {
      label.foregroundStyle(.secondary).gridColumnAlignment(.trailing)
      Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
  }
}
