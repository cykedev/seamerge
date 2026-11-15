import MergeModel
import SwiftUI

/// The form of the window Settings: how the code is drawn, which every window shows at once,
/// and how each new window starts.
struct SettingsView: View {
  @Bindable var settings: UserSettings

  /// The families of fonts of fixed width to choose from, besides the font of the system.
  let fontFamilies: [String]

  var body: some View {
    Form {
      textSection
      Section {
        Picker(selection: $settings.comparisonMode) {
          ForEach(SessionFooterView.modeCommands, id: \.self) { command in
            if let mode = command.comparisonMode {
              Text(command.title).tag(mode)
            }
          }
        } label: {
          Text(SessionCommand.comparisonModeLabel)
        }
        Toggle(SessionCommand.toggleSyntaxHighlighting.title, isOn: $settings.highlightsSyntax)
        Toggle(SessionCommand.toggleLineWrapping.title, isOn: $settings.wrapsLines)
        Toggle(SessionCommand.toggleLineAlignment.title, isOn: $settings.alignsLines)
        Toggle(SessionCommand.toggleInvisibles.title, isOn: $settings.showsInvisibles)
        Toggle(isOn: $settings.showsBase) {
          Text(
            "Show Base", bundle: .module,
            comment: "View menu command, and the setting of whether a new merge shows the base.")
        }
      } header: {
        Text(
          "New Windows", bundle: .module,
          comment: "Settings: heading of the group of how a new window starts.")
      } footer: {
        Text(
          "Each window starts like this. The switches in a window’s footer change only that window.",
          bundle: .module, comment: "Settings: note below the group of how a new window starts.")
      }
      Section {
        Toggle(isOn: $settings.goesToNextConflict) {
          Text(
            "Go to Next Conflict After Choosing", bundle: .module,
            comment: "Settings: whether Use A and the like go on to the next open conflict.")
          Text(
            "After Use A, Use B and the like on an open conflict.", bundle: .module,
            comment: "Settings: when the window goes on to the next conflict.")
        }
      } header: {
        Text("Merging", bundle: .module, comment: "Settings: heading of the merge group.")
      }
    }
    .formStyle(.grouped)
    .frame(width: WindowMetrics.settingsWidth)
    .fixedSize()
  }

  private var textSection: some View {
    Section {
      Picker(selection: $settings.fontFamily) {
        Text("SF Mono", bundle: .module, comment: "Settings: the monospaced font of the system.")
          .tag(String?.none)
        Divider()
        ForEach(fontFamilies, id: \.self) { family in
          Text(verbatim: family).tag(String?.some(family))
        }
      } label: {
        Text("Font", bundle: .module, comment: "Settings: the font of the code.")
      }
      Picker(selection: fontSizeSelection) {
        ForEach(Self.fontSizes, id: \.self) { size in
          Text(Self.sizeText(size)).tag(size)
        }
      } label: {
        Text("Size", bundle: .module, comment: "Settings: the size of the code.")
      }
      Picker(selection: $settings.lineSpacing) {
        ForEach(LineSpacing.allCases, id: \.self) { spacing in
          Text(spacing.title).tag(spacing)
        }
      } label: {
        Text("Line Spacing", bundle: .module, comment: "Settings: how far apart lines are.")
      }
      Picker(selection: tabWidthSelection) {
        ForEach(Self.tabWidths, id: \.self) { width in
          Text(Self.tabWidthText(width)).tag(width)
        }
      } label: {
        Text("Tab Width", bundle: .module, comment: "Settings: the width of a tab.")
      }
    } header: {
      Text("Text", bundle: .module, comment: "Settings: heading of the group of the code font.")
    } footer: {
      Text(
        "Every window shows the change at once.", bundle: .module,
        comment: "Settings: note below the group of the code font.")
    }
  }

  /// The sizes of the code to choose from, in whole points.
  static let fontSizes = Array(
    Int(UserSettings.fontSizes.lowerBound)...Int(UserSettings.fontSizes.upperBound))

  /// The widths of a tab to choose from, in spaces.
  static let tabWidths = Array(UserSettings.tabWidths)

  /// The size chosen in the menu, in whole points, so that a size between two in the menu, which
  /// only the user defaults can hold, still selects the nearest.
  var fontSizeSelection: Binding<Int> {
    Binding(
      get: { Int(settings.fontSize.rounded()) },
      set: { settings.fontSize = CGFloat($0) })
  }

  /// The width of a tab chosen in the menu.
  var tabWidthSelection: Binding<Int> {
    $settings.tabWidth
  }

  /// The name of a size in the menu, such as 13 pt.
  static func sizeText(_ size: Int) -> String {
    String(
      localized: "\(size) pt", bundle: .module,
      comment: "Settings: the size of the code, such as 13 pt.")
  }

  /// The name of a width of a tab in the menu, such as 4 spaces.
  static func tabWidthText(_ width: Int) -> String {
    String(
      localized: "\(width) spaces", bundle: .module,
      comment: "Settings: the width of a tab, such as 4 spaces.")
  }
}

extension LineSpacing {
  /// The name of the spacing in Settings.
  var title: String {
    switch self {
    case .compact:
      String(localized: "Compact", bundle: .module, comment: "Settings: lines close together.")
    case .standard:
      String(
        localized: "Standard", bundle: .module, comment: "Settings: lines at standard spacing.")
    case .spacious:
      String(localized: "Spacious", bundle: .module, comment: "Settings: lines far apart.")
    }
  }
}
