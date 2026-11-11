import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("mergecli: \(message)\n".utf8))
  exit(ExitStatus.failure.rawValue)
}

let invocation: Invocation
do {
  invocation = try Invocation(parsing: Array(CommandLine.arguments.dropFirst()))
} catch {
  fail("\(error.message)\n\n\(Invocation.usage)")
}

do {
  let status: ExitStatus
  switch invocation.command {
  case .help:
    print(Invocation.usage)
    status = .clean
  case .diff(let a, let b):
    status = try runDiff(a: a, b: b, options: invocation)
  case .merge(let base, let a, let b):
    status = try runMerge(base: base, a: a, b: b, options: invocation)
  }
  exit(status.rawValue)
} catch {
  fail(error.message)
}
