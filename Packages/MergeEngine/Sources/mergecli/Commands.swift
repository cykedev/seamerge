import Foundation
import MergeEngine

enum ExitStatus: Int32 {
  case clean = 0
  case differences = 1
  case failure = 2
}

struct CommandError: Error {
  let message: String
}

func readFile(_ path: String) throws(CommandError) -> Data {
  do {
    return try Data(contentsOf: URL(fileURLWithPath: path))
  } catch {
    throw CommandError(message: "cannot read \(path): \(error.localizedDescription)")
  }
}

func runDiff(a pathA: String, b pathB: String, options: Invocation) throws(CommandError)
  -> ExitStatus
{
  let dataA = try readFile(pathA)
  let dataB = try readFile(pathB)
  let diff: Diff
  do {
    diff = try Diff(dataA, dataB, whitespace: options.whitespace)
  } catch {
    throw CommandError(message: "diff failed: \(error)")
  }

  print("a: \(pathA) (\(diff.a.lineCount) lines)")
  print("b: \(pathB) (\(diff.b.lineCount) lines)")
  print("whitespace: \(options.whitespace.name)")

  for block in diff.blocks {
    let kind =
      switch block.kind {
      case .equal: "equal"
      case .changed: block.isInsertion ? "insert" : block.isDeletion ? "delete" : "change"
      }
    print(
      "\(kind.rightPadded(7)) a \(lineNumbers(block.a).rightPadded(12)) b \(lineNumbers(block.b))")
    guard block.kind == .changed else { continue }

    if options.showsTokens && block.a.lines.count == block.b.lines.count {
      for (lineA, lineB) in zip(block.a.lines, block.b.lines) {
        print("    ~ " + tokenMarkup(diff.a.line(lineA), diff.b.line(lineB)))
      }
    } else {
      let lines =
        listing(block.a, in: diff.a, prefix: "    - ")
        + listing(block.b, in: diff.b, prefix: "    + ")
      for line in lines { print(line) }
    }
  }

  let changes = diff.changes.count
  print(changes == 0 ? "identical" : "\(changes) change\(changes == 1 ? "" : "s")")
  return changes == 0 ? .clean : .differences
}

/// A line pair as one line with `[-removed-]` and `{+added+}` markup.
func tokenMarkup(_ lineA: Data, _ lineB: Data) -> String {
  guard let diff = try? TokenDiff(lineA, lineB) else {
    return displayed(lineA).text + " → " + displayed(lineB).text
  }
  return diff.blocks.map { block in
    let removed = displayed(diff.a.bytes(tokens: block.a.tokens)).text
    let added = displayed(diff.b.bytes(tokens: block.b.tokens)).text
    switch block.kind {
    case .equal: return removed
    case .changed:
      return (block.a.isEmpty ? "" : "[-\(removed)-]") + (block.b.isEmpty ? "" : "{+\(added)+}")
    }
  }.joined()
}

func runMerge(base pathBase: String, a pathA: String, b pathB: String, options: Invocation)
  throws(CommandError) -> ExitStatus
{
  let merge: Merge
  do {
    merge = try Merge(
      base: try readFile(pathBase), a: try readFile(pathA), b: try readFile(pathB),
      whitespace: options.whitespace, strategy: options.strategy)
  } catch let error as CommandError {
    throw error
  } catch {
    throw CommandError(message: "merge failed: \(error)")
  }

  // When the result goes to standard output, the listing goes to stderr.
  let log: (String) -> Void =
    options.outputPath == "-"
    ? { FileHandle.standardError.write(Data(($0 + "\n").utf8)) } : { print($0) }

  if options.listsBlocks {
    log("base: \(pathBase) (\(merge.base.lineCount) lines)")
    log("a:    \(pathA) (\(merge.a.lineCount) lines)")
    log("b:    \(pathB) (\(merge.b.lineCount) lines)")
    log("whitespace: \(options.whitespace.name), strategy: \(options.strategy.name)")
    for (index, block) in merge.blocks.enumerated() {
      log(summary(of: block, number: index + 1))
      for line in details(of: block, in: merge) { log(line) }
    }
    let conflicts = merge.conflictCount
    log(conflicts == 0 ? "no conflicts" : "\(conflicts) conflict\(conflicts == 1 ? "" : "s")")
  }

  if let outputPath = options.outputPath {
    let labels = Merge.ConflictLabels(a: pathA, base: pathBase, b: pathB)
    let text = merge.result(markingConflicts: options.conflictStyle, labels: labels).data
    if outputPath == "-" {
      FileHandle.standardOutput.write(text)
    } else {
      do {
        try text.write(to: URL(fileURLWithPath: outputPath))
      } catch {
        throw CommandError(message: "cannot write \(outputPath): \(error.localizedDescription)")
      }
    }
  }
  return merge.hasConflicts ? .differences : .clean
}

func summary(of block: Merge.Block, number: Int) -> String {
  let kind =
    switch block.kind {
    case .unchanged: "unchanged"
    case .changedInA: "A"
    case .changedInB: "B"
    case .changedInBoth: "A=B"
    case .conflict: "CONFLICT"
    }
  return "#\(String(number).rightPadded(3)) \(kind.rightPadded(9))"
    + " base \(lineNumbers(block.base).rightPadded(10))"
    + " a \(lineNumbers(block.a).rightPadded(10))"
    + " b \(lineNumbers(block.b))"
}

/// The lines that explain a block: the base and every side that differs.
func details(of block: Merge.Block, in merge: Merge) -> [String] {
  switch block.kind {
  case .unchanged:
    []
  case .changedInA, .changedInBoth:
    listing(block.base, in: merge.base, prefix: "    base| ")
      + listing(block.a, in: merge.a, prefix: "    a   | ")
  case .changedInB:
    listing(block.base, in: merge.base, prefix: "    base| ")
      + listing(block.b, in: merge.b, prefix: "    b   | ")
  case .conflict:
    listing(block.base, in: merge.base, prefix: "    base| ")
      + listing(block.a, in: merge.a, prefix: "    a   | ")
      + listing(block.b, in: merge.b, prefix: "    b   | ")
  }
}
