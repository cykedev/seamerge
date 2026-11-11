/// An error in reading or writing the text of a file.
///
/// Errors of the file system itself are passed on as Foundation reports them.
public enum TextIOError: Error, Sendable, Hashable {
  /// The bytes of the file are not valid text in the encoding it was asked to be read in.
  case invalidBytes(TextEncoding)

  /// The text contains characters that the encoding it was asked to be written in cannot
  /// represent.
  case unrepresentableText(TextEncoding)
}
