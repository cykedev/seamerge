import Foundation

/// What a window of two folders says in place of the lines while it shows none of their files.
enum CollectionPlaceholder: Equatable {
  /// The folders are being compared and no file to show is known yet.
  case comparing

  /// The folders are compared and hold the same files.
  case sameFiles

  /// The list holds files, but none of them is shown.
  case noFile

  /// What the window says first.
  var title: String {
    switch self {
    case .comparing:
      String(
        localized: "Comparing…", bundle: .module,
        comment: "Window of two folders: no file is shown yet while the folders are compared.")
    case .sameFiles:
      String(
        localized: "The folders have the same files.", bundle: .module,
        comment: "Window of two folders: no file differs.")
    case .noFile:
      String(
        localized: "No File Selected", bundle: .module,
        comment: "Window of two folders: the list holds files, but none is shown.")
    }
  }

  /// What the window says below the title: the next step, if there is one.
  var message: String? {
    switch self {
    case .comparing, .noFile:
      nil
    case .sameFiles:
      String(
        localized: "Choose View > Show Identical Files to list them.", bundle: .module,
        comment: "Window of two folders without differences: how to list the files anyway.")
    }
  }
}
