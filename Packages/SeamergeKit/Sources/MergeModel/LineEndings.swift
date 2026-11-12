import TextIO

/// How the lines of a file end.
public enum LineEndings: Sendable, Hashable {
  /// Every line ends in LF, as on macOS and Linux.
  case lf

  /// Every line ends in CR followed by LF, as on Windows.
  case crlf

  /// Every line ends in CR, as on classic Mac OS.
  case cr

  /// The lines end in more than one way.
  case mixed

  /// The line endings of a text as TextIO describes them.
  init(_ style: LineEndingStyle) {
    self =
      switch style {
      case .uniform(.lf): .lf
      case .uniform(.crlf): .crlf
      case .uniform(.cr): .cr
      case .mixed: .mixed
      }
  }
}
