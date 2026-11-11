import MergeEngine

/// A parsed command line.
struct Invocation {
  enum Command {
    case diff(a: String, b: String)
    case merge(base: String, a: String, b: String)
    case help
  }

  var command: Command
  var whitespace = Whitespace.exact
  var strategy = MergeStrategy.optimal
  var conflictStyle = Merge.ConflictStyle.diff3
  var outputPath: String?
  var listsBlocks = true
  var showsTokens = false

  static let usage = """
    usage: mergecli diff [options] <a> <b>
           mergecli merge [options] <base> <a> <b> [-o <file>]

    Compares or merges files with the Perforce diff/merge engine.
    For merge, <a> is the incoming side (theirs) and <b> the own side (yours).

    options:
      -dl                 ignore line endings
      -db                 ignore changes in the amount of whitespace
      -dw                 ignore all whitespace
      --tokens            diff: show changes within lines
      --strategy <name>   merge: optimal (default), guarded, diff3,
                          guardedDiff3, twoWay
      --style <name>      merge: conflict markers diff3 (default) or merge
      -o <file>           merge: write the result with conflict markers;
                          "-" writes to standard output
      -q                  merge: do not list the blocks
      -h, --help          show this help

    exit status: 0 no differences or conflicts, 1 differences or conflicts,
                 2 error
    """
}

struct UsageError: Error {
  let message: String
}

extension Invocation {
  init(parsing arguments: [String]) throws(UsageError) {
    var remaining = arguments[...]
    guard let name = remaining.popFirst() else { throw UsageError(message: "missing command") }
    guard ["diff", "merge", "help", "-h", "--help"].contains(name) else {
      throw UsageError(message: "unknown command '\(name)'")
    }

    func requireCommand(_ command: String, for option: String) throws(UsageError) {
      guard name == command else {
        throw UsageError(message: "\(option) is only valid for \(command)")
      }
    }

    var options = Invocation(command: .help)
    var paths: [String] = []

    func value(for option: String) throws(UsageError) -> String {
      guard let value = remaining.popFirst() else {
        throw UsageError(message: "\(option) needs a value")
      }
      return value
    }

    while let argument = remaining.popFirst() {
      switch argument {
      case "-dl": options.whitespace = .ignoreLineEndings
      case "-db": options.whitespace = .ignoreAmount
      case "-dw": options.whitespace = .ignoreAll
      case "--tokens":
        try requireCommand("diff", for: argument)
        options.showsTokens = true
      case "-q":
        try requireCommand("merge", for: argument)
        options.listsBlocks = false
      case "-o":
        try requireCommand("merge", for: argument)
        options.outputPath = try value(for: argument)
      case "--strategy":
        try requireCommand("merge", for: argument)
        let strategyName = try value(for: argument)
        guard let strategy = MergeStrategy.allCases.first(where: { $0.name == strategyName }) else {
          throw UsageError(message: "unknown strategy '\(strategyName)'")
        }
        options.strategy = strategy
      case "--style":
        try requireCommand("merge", for: argument)
        switch try value(for: argument) {
        case "diff3": options.conflictStyle = .diff3
        case "merge": options.conflictStyle = .merge
        case let style: throw UsageError(message: "unknown conflict style '\(style)'")
        }
      case "-h", "--help":
        self = Invocation(command: .help)
        return
      case "-":
        throw UsageError(message: "reading standard input is not supported")
      case let option where option.hasPrefix("-"):
        throw UsageError(message: "unknown option '\(option)'")
      default: paths.append(argument)
      }
    }

    switch (name, paths.count) {
    case ("diff", 2): options.command = .diff(a: paths[0], b: paths[1])
    case ("merge", 3): options.command = .merge(base: paths[0], a: paths[1], b: paths[2])
    case ("help", _), ("-h", _), ("--help", _): options.command = .help
    case ("diff", _): throw UsageError(message: "diff needs two files")
    default: throw UsageError(message: "merge needs three files")
    }
    self = options
  }
}

extension Whitespace {
  /// The name shown in listings.
  var name: String {
    switch self {
    case .exact: "exact"
    case .ignoreLineEndings: "ignoreLineEndings"
    case .ignoreAmount: "ignoreAmount"
    case .ignoreAll: "ignoreAll"
    }
  }
}

extension MergeStrategy {
  /// The name used by `--strategy` and shown in listings.
  var name: String {
    switch self {
    case .optimal: "optimal"
    case .guarded: "guarded"
    case .diff3: "diff3"
    case .guardedDiff3: "guardedDiff3"
    case .twoWay: "twoWay"
    }
  }
}
