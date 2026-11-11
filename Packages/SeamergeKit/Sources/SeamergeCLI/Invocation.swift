/// What the arguments of the command ask for.
enum Invocation {
  /// A three-way merge: `seamerge merge …`.
  case merge(MergeArguments)

  /// A comparison: `seamerge diff …`, or the short form `seamerge <old> <new>`.
  case diff(DiffArguments)

  /// `--help`.
  case help

  /// `--version`.
  case version

  /// Reads the arguments that follow the name of the command.
  ///
  /// An option takes the next argument as its value, even one that starts with a dash such as
  /// `--help`; after `--`, every argument is a file. Anywhere else, `--help` and `--version` win
  /// over every other argument, including wrong ones.
  ///
  /// - Throws: ``CommandError`` with a usage case if the arguments do not form a valid invocation.
  init(arguments: [String]) throws(CommandError) {
    let isMerge = arguments.first == "merge"
    let scanned =
      switch arguments.first {
      case "merge": Self.scan(arguments.dropFirst(), options: Option.merge, filesFollow: false)
      case "diff": Self.scan(arguments.dropFirst(), options: Option.diff, filesFollow: true)
      default: Self.scan(arguments[...], options: Option.diff, filesFollow: true)
      }
    if scanned.asksForHelp {
      self = .help
    } else if scanned.asksForVersion {
      self = .version
    } else if let error = scanned.firstError {
      throw error
    } else if isMerge {
      self = .merge(try MergeArguments(scanned))
    } else {
      self = .diff(try DiffArguments(scanned))
    }
  }

  /// Splits arguments into the values of `options` and the remaining operands.
  ///
  /// The scan goes on after a wrong argument, so that `--help` further on still counts.
  ///
  /// - Parameter filesFollow: Whether files follow the options, so that a file whose name starts
  ///   with a dash may be taken for an unknown option.
  private static func scan(
    _ arguments: ArraySlice<String>, options: [Option], filesFollow: Bool
  ) -> ScannedArguments {
    var scanned = ScannedArguments()
    var remaining = arguments.makeIterator()
    var acceptsOptions = true
    while let argument = remaining.next() {
      if !acceptsOptions || !argument.hasPrefix("-") || argument == "-" {
        scanned.operands.append(argument)
      } else if argument == "--" {
        acceptsOptions = false
      } else if argument == "--help" {
        scanned.asksForHelp = true
      } else if argument == "--version" {
        scanned.asksForVersion = true
      } else if let option = options.first(where: { $0.rawValue == argument }) {
        if let value = remaining.next() {
          if scanned.values[option] != nil { scanned.record(.repeatedOption(argument)) }
          scanned.values[option] = value
        } else {
          scanned.record(.missingValue(option: argument))
        }
      } else {
        scanned.record(filesFollow ? .unknownOptionOrFile(argument) : .unknownOption(argument))
      }
    }
    return scanned
  }
}

/// An option that takes a value.
enum Option: String {
  case base = "--base"
  case local = "--local"
  case remote = "--remote"
  case output = "--output"
  case baseLabel = "--label-base"
  case localLabel = "--label-local"
  case remoteLabel = "--label-remote"
  case path = "--path"
  case leftLabel = "--label-left"
  case rightLabel = "--label-right"

  /// The options of `seamerge merge`.
  static let merge: [Option] = [
    .base, .local, .remote, .output, .baseLabel, .localLabel, .remoteLabel,
  ]

  /// The options of `seamerge diff`.
  static let diff: [Option] = [.path, .leftLabel, .rightLabel]
}

/// The arguments of one form of the command, split into option values and operands.
struct ScannedArguments {
  /// The value of each option that was given.
  var values: [Option: String] = [:]

  /// The arguments that are not options or their values, in their order.
  var operands: [String] = []

  /// Whether `--help` stands where an option may stand.
  var asksForHelp = false

  /// Whether `--version` stands where an option may stand.
  var asksForVersion = false

  /// The first thing wrong with the arguments, if any.
  private(set) var firstError: CommandError?

  /// Notes what is wrong, unless something before it was wrong already.
  mutating func record(_ error: CommandError) {
    if firstError == nil { firstError = error }
  }

  /// The value of an option that must be given.
  ///
  /// - Throws: ``CommandError/missingOption(_:)`` if it was not given.
  func requiredValue(of option: Option) throws(CommandError) -> String {
    guard let value = values[option] else { throw .missingOption(option.rawValue) }
    return value
  }
}

/// The arguments of `seamerge merge`, as they were given.
struct MergeArguments {
  /// The path of the common ancestor; `nil` or empty for a merge without one.
  var base: String?

  /// The path of `LOCAL`, shown on the right.
  var local: String

  /// The path of `REMOTE`, shown on the left.
  var remote: String

  /// The path the result is saved to.
  var output: String

  /// The name for the base given on the command line.
  var baseLabel: String?

  /// The name for `LOCAL` given on the command line.
  var localLabel: String?

  /// The name for `REMOTE` given on the command line.
  var remoteLabel: String?

  fileprivate init(_ scanned: ScannedArguments) throws(CommandError) {
    if let operand = scanned.operands.first { throw .unexpectedArgument(operand) }
    base = scanned.values[.base]
    local = try scanned.requiredValue(of: .local)
    remote = try scanned.requiredValue(of: .remote)
    output = try scanned.requiredValue(of: .output)
    baseLabel = scanned.values[.baseLabel]
    localLabel = scanned.values[.localLabel]
    remoteLabel = scanned.values[.remoteLabel]
  }
}

/// The arguments of `seamerge diff`, as they were given.
struct DiffArguments {
  /// The path of the older file, shown on the left.
  var left: String

  /// The path of the newer file, shown on the right.
  var right: String

  /// The path to show for both files, such as the path of the file in the repository.
  var path: String?

  /// The name for the left file given on the command line.
  var leftLabel: String?

  /// The name for the right file given on the command line.
  var rightLabel: String?

  fileprivate init(_ scanned: ScannedArguments) throws(CommandError) {
    switch scanned.operands.count {
    case 0: throw .missingFiles(count: 2)
    case 1: throw .missingFiles(count: 1)
    case 2: break
    default: throw .unexpectedArgument(scanned.operands[2])
    }
    left = scanned.operands[0]
    right = scanned.operands[1]
    path = scanned.values[.path]
    leftLabel = scanned.values[.leftLabel]
    rightLabel = scanned.values[.rightLabel]
  }
}
