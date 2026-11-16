import MergeModel
import PaneKit
import SwiftUI

/// The header above a single column: both sides of the comparison in the order the column reads
/// them, the side whose lines come first, an arrow, then the other side, each with its badge,
/// its name and a quiet button for its details.
///
/// A click on a side opens its details as well.
struct ColumnHeaderView: View {
  /// The side whose lines come first in a changed block, then the other one.
  let headers: [SideHeader]
  let theme: Theme

  @State private var detailsShown: Role?

  var body: some View {
    HStack(spacing: WindowMetrics.headerSpacing) {
      ForEach(Array(headers.enumerated()), id: \.element.role) { index, header in
        if index > 0 {
          Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        side(header)
      }
      Spacer(minLength: 0)
    }
    .lineLimit(1)
    .padding(.horizontal, WindowMetrics.headerInset)
    .frame(height: WindowMetrics.headerHeight)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(spokenName))
  }

  /// The names and the button ⓘ of the side of `header`, with the popover of its details.
  private func side(_ header: SideHeader) -> some View {
    HStack(spacing: WindowMetrics.headerSpacing) {
      SideNamesView(header: header, theme: theme)
      SideDetailsButton(header: header) { detailsShown = header.role }
    }
    .contentShape(Rectangle())
    .onTapGesture { detailsShown = header.role }
    .popover(
      isPresented: Binding(
        get: { detailsShown == header.role },
        set: { if !$0, detailsShown == header.role { detailsShown = nil } }),
      arrowEdge: .bottom
    ) {
      SideDetailsView(header: header, theme: theme)
    }
  }

  /// What VoiceOver calls the header: both sides in the order of the column.
  var spokenName: String {
    guard headers.count == 2 else { return headers.first?.spokenName ?? "" }
    return String(
      localized: "\(headers[0].spokenName) to \(headers[1].spokenName)", bundle: .module,
      comment:
        "VoiceOver: the header of a single column that shows both files, such as A, old.swift to B, new.swift."
    )
  }
}
