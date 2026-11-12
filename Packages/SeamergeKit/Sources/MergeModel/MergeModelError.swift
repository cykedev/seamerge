/// An error in opening a session or in comparing its text.
public enum MergeModelError: Error, Sendable, Hashable {
  /// The input of the role is binary and cannot be compared as text.
  case binaryInput(Role)

  /// An input is 2 GiB or larger, more than the comparison can index.
  case inputTooLarge

  /// Memory for the comparison could not be allocated.
  case outOfMemory

  /// The comparison failed unexpectedly, which indicates a bug.
  case comparisonFailed
}
