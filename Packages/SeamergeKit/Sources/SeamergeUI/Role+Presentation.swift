import MergeModel
import PaneKit

extension Role {
  /// The letter that names the input on its badge: A, Base or B.
  var letter: String {
    switch self {
    case .a: String(localized: "A", bundle: .module, comment: "The badge of the incoming side.")
    case .base:
      String(localized: "Base", bundle: .module, comment: "The badge of the common ancestor.")
    case .b: String(localized: "B", bundle: .module, comment: "The badge of the own side.")
    }
  }

  /// The color of the input.
  var colorRole: ColorRole {
    switch self {
    case .a: .a
    case .base: .base
    case .b: .b
    }
  }
}
