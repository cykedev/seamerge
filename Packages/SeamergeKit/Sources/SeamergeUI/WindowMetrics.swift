import Foundation

/// The sizes and distances of the window around the panes, on the 4-point grid.
enum WindowMetrics {
  /// The height of a pane header.
  static let headerHeight: CGFloat = 28

  /// The height of the footer, the bottom border of the window.
  static let footerHeight: CGFloat = 28

  /// The distance of the content of the footer from the edges of the window, as far as the
  /// content of a header from the edges of its pane.
  static let footerInset: CGFloat = 12

  /// The distance between the two pop-up buttons of the footer.
  static let footerPopUpSpacing: CGFloat = 8

  /// The distance between the comparison mode and the toggles in the footer.
  static let footerGroupSpacing: CGFloat = 16

  /// The distance between two toggles of the footer.
  static let footerToggleSpacing: CGFloat = 4

  /// The width of a toggle of the footer that shows its symbol alone: the same for every
  /// symbol, so that the toggles stand evenly.
  static let footerSymbolButtonWidth: CGFloat = 28

  /// The radius of the corners of the gray area behind a toggle of the footer that is on, and
  /// of the outline of one in the mixed state.
  static let footerToggleCornerRadius: CGFloat = 5

  /// The width of the outline of a toggle of the footer in the mixed state.
  static let footerToggleOutlineWidth: CGFloat = 1

  /// The least room on either side of the symbol in a toggle of the footer.
  static let footerSymbolPadding: CGFloat = 4

  /// The height of the line below the result header that says Git no longer waits.
  static let noticeHeight: CGFloat = 24

  /// The distance between the title of a pop-up menu in a header and its chevron.
  static let menuIndicatorSpacing: CGFloat = 2

  /// The distance of a header's content from the edges of its pane.
  static let headerInset: CGFloat = 12

  /// The distance between the parts of a header.
  static let headerSpacing: CGFloat = 8

  /// The least width and height of a control that is clicked.
  static let minimumHitTarget: CGFloat = 20

  /// The height of the badge of a side.
  static let badgeHeight: CGFloat = 16

  /// The room on either side of the letter in a badge.
  static let badgePadding: CGFloat = 4

  /// The margin around the details of a side.
  static let detailsInset: CGFloat = 16

  /// The distance between the title of the details and their facts.
  static let detailsSpacing: CGFloat = 12

  /// The distance between the facts of the details.
  static let detailsRowSpacing: CGFloat = 4

  /// The widest the details of a side get before their lines wrap.
  static let detailsMaximumWidth: CGFloat = 400

  /// The part of the window's height that the panes above the result take at first.
  static let sourcesFraction: CGFloat = 0.55

  /// The room the title bar keeps before the title for the window's buttons.
  static let titlebarControlsWidth: CGFloat = 80

  /// The least room between the subtitle and the items of the toolbar.
  static let toolbarSpacing: CGFloat = 16

  /// The width of the field of Go to Line.
  static let lineFieldWidth: CGFloat = 200

  /// The least width of a window, at which the toolbar shows the title, the count with its
  /// arrows, and Done without moving any of them into its overflow menu.
  static let minimumToolbarWidth: CGFloat = 640

  /// The distance between the title and the message of a comparison that cannot be shown.
  static let unavailableSpacing: CGFloat = 8

  /// The widest the title and the message of a comparison that cannot be shown get.
  static let unavailableWidth: CGFloat = 400

  /// The least room around the title and the message of a comparison that cannot be shown.
  static let unavailableInset: CGFloat = 24

  /// The width of the list of files in the sidebar of a window that compares several files.
  static let sidebarWidth: CGFloat = 220

  /// The distance of the filter field from the edges of the sidebar.
  static let sidebarFilterInset: CGFloat = 8

  /// The distance of the sign of a file, and of the heading of a folder, from the start of their
  /// row in the list of the sidebar.
  static let fileRowInset: CGFloat = 2

  /// The width of the sign of what happened to a file in the list of the sidebar, which a file
  /// without a sign keeps free, so that the names line up.
  static let fileSignWidth: CGFloat = 16

  /// The room between the sign, the name and the dot of a file in the list of the sidebar.
  static let fileRowSpacing: CGFloat = 6

  /// The size of the dot of a file with unsaved changes in the list of the sidebar, in points.
  static let changedFileDotSize: CGFloat = 8

  /// The distance of that dot from the end of its row.
  static let changedFileDotInset: CGFloat = 8

  /// The narrowest the list of files gets before it collapses.
  static let minimumSidebarWidth: CGFloat = 160

  /// The widest the list of files gets.
  static let maximumSidebarWidth: CGFloat = 400

  /// The size of a new window.
  static let defaultContentSize = CGSize(width: 1280, height: 800)

  /// The least height of the panes above the result and of the result, so that the divider
  /// between them stays visible and a few rows show.
  static let minimumPaneHeight: CGFloat = 120

  /// The width of the window Settings.
  static let settingsWidth: CGFloat = 480

  /// The distance between the edges of a page of Settings that AppKit lays out and its content,
  /// as far as the grouped form of the page General keeps its groups from the edges.
  static let settingsInset: CGFloat = 20

  /// The distance between a list of Settings and the buttons below it, and between those and
  /// the note below them.
  static let settingsSpacing: CGFloat = 8

  /// The distance between the parts of a page of Settings.
  static let settingsGroupSpacing: CGFloat = 16

  /// The height of the table of ignore rules: its header and seven rows.
  static let ignoreRuleTableHeight: CGFloat = 200

  /// The height of the square buttons below a table that add and remove its rows.
  static let tableButtonHeight: CGFloat = 24

  /// The room on either side of the title of a square button below a table.
  static let tableButtonPadding: CGFloat = 12

  /// The width of the column of the switches of the ignore rules.
  static let ignoreRuleSwitchColumnWidth: CGFloat = 24

  /// The width of the column of the names of the ignore rules.
  static let ignoreRuleNameColumnWidth: CGFloat = 140

  /// The height of the field in which a rule is tried.
  static let ruleTrialHeight: CGFloat = 112

  /// The distance between the text of the field in which a rule is tried and its edges.
  static let ruleTrialInset: CGFloat = 4

  /// The distance between the parts of a row of the table of ignore rules.
  static let ignoreRuleCellSpacing: CGFloat = 4

  /// The distance between the parts of the window Keyboard Shortcuts, and between its groups.
  static let shortcutOverviewSpacing: CGFloat = 16

  /// The distance between the two columns of the window Keyboard Shortcuts.
  static let shortcutOverviewColumnSpacing: CGFloat = 32

  /// The width of each column of the window Keyboard Shortcuts: room for the longest command
  /// with its single keys and its shortcut.
  static let shortcutOverviewColumnWidth: CGFloat = 320

  /// The distance between the edges of the window Keyboard Shortcuts and what it shows.
  static let shortcutOverviewInset: CGFloat = 24

  /// The distance between the rows of a group in the window Keyboard Shortcuts.
  static let shortcutOverviewRowSpacing: CGFloat = 4

  /// The distance between a command, its single keys and its shortcut.
  static let shortcutOverviewKeySpacing: CGFloat = 12
}
