import MergeModel
import SwiftUI

/// The overview of the keyboard shortcuts: the shortcuts of a merge or of a comparison, by menu,
/// in two columns that show them all at a glance.
struct ShortcutOverviewView: View {
  /// The kind of window whose shortcuts the overview shows.
  @State var kind: Session.Kind

  var body: some View {
    let columns = Self.split(overview.groups)
    VStack(spacing: WindowMetrics.shortcutOverviewSpacing) {
      kindPicker
      HStack(alignment: .top, spacing: WindowMetrics.shortcutOverviewColumnSpacing) {
        ForEach(columns.indices, id: \.self) { index in
          VStack(alignment: .leading, spacing: WindowMetrics.shortcutOverviewSpacing) {
            ForEach(columns[index]) { group in
              groupBlock(group)
            }
          }
          .frame(width: WindowMetrics.shortcutOverviewColumnWidth, alignment: .topLeading)
        }
      }
      singleKeyNote
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(WindowMetrics.shortcutOverviewInset)
    .fixedSize()
  }

  private var overview: ShortcutOverview { ShortcutOverview(kind: kind) }

  private var kindPicker: some View {
    Picker(selection: $kind) {
      Text("Merge", bundle: .module, comment: "Keyboard Shortcuts: the shortcuts of a merge.")
        .tag(Session.Kind.merge)
      Text(
        "Comparison", bundle: .module,
        comment: "Keyboard Shortcuts: the shortcuts of a comparison of two files."
      )
      .tag(Session.Kind.diff)
    } label: {
      Text("Window", bundle: .module, comment: "Keyboard Shortcuts: the choice of the window.")
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
  }

  private var singleKeyNote: some View {
    Text(ShortcutOverview.singleKeyNote(for: kind))
  }

  private func groupBlock(_ group: ShortcutOverview.Group) -> some View {
    VStack(alignment: .leading, spacing: WindowMetrics.shortcutOverviewRowSpacing) {
      Text(group.menu.title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Grid(
        alignment: .leading, horizontalSpacing: WindowMetrics.shortcutOverviewKeySpacing,
        verticalSpacing: WindowMetrics.shortcutOverviewRowSpacing
      ) {
        ForEach(group.entries) { entry in
          // VoiceOver reads each row as one element, the title cell, which says it all.
          GridRow {
            Text(entry.title)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel(entry.spokenDescription)
            Text(entry.singleKeys ?? "")
              .foregroundStyle(.secondary)
              .gridColumnAlignment(.trailing)
              .accessibilityHidden(true)
            Text(entry.shortcut ?? "")
              .gridColumnAlignment(.trailing)
              .accessibilityHidden(true)
          }
        }
      }
    }
  }

  /// The groups in two columns of about equal length, each group whole.
  private static func split(_ groups: [ShortcutOverview.Group]) -> [[ShortcutOverview.Group]] {
    let total = groups.reduce(0) { $0 + $1.entries.count + 2 }
    var left: [ShortcutOverview.Group] = []
    var count = 0
    var rest = groups[...]
    while let group = rest.first, count + (group.entries.count + 2) / 2 <= total / 2 {
      left.append(group)
      count += group.entries.count + 2
      rest = rest.dropFirst()
    }
    return [left, Array(rest)]
  }
}
