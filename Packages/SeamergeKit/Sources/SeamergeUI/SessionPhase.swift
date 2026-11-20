/// What a session window shows of the lines of its files.
///
/// The window takes the commands of the lines only while it shows them and brings back no earlier
/// comparison; otherwise it takes those of a window of several files and of the footer.
enum SessionPhase {
  /// The headers of the files above empty panes, while the task gets the lines ready.
  case loading(Task<Void, Never>)

  /// Why the files cannot be compared, in place of their lines.
  case unavailable(UnavailableComparison)

  /// Why a window of several files shows none of them, in place of the lines.
  case placeholder(CollectionPlaceholder)

  /// The lines of the files.
  case ready

  /// The task that gets the lines ready while the window waits for them, or `nil`.
  var filling: Task<Void, Never>? {
    if case .loading(let filling) = self { filling } else { nil }
  }

  /// The comparison whose files cannot be compared, or `nil`.
  var unavailable: UnavailableComparison? {
    if case .unavailable(let comparison) = self { comparison } else { nil }
  }

  /// What the window says while it shows no file of its collection, or `nil`.
  var placeholder: CollectionPlaceholder? {
    if case .placeholder(let placeholder) = self { placeholder } else { nil }
  }

  /// Whether the window shows lines, or will once they are ready, rather than why it shows none.
  var showsLines: Bool {
    switch self {
    case .loading, .ready: true
    case .unavailable, .placeholder: false
    }
  }
}
