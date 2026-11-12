/// The roles that have a color of their own.
///
/// Each role has a surface value, from which the tints of rows and runs are derived, and a
/// symbol value for everything that has to stand out on a surface: markers in the gutter,
/// badges and toggles.
public enum ColorRole: Sendable, Hashable {
  /// The incoming side, blue.
  case a
  /// The common ancestor, yellow.
  case base
  /// The own side, green.
  case b
  /// A conflict that is still open, red.
  case conflict
}
