import TextBasics

extension PatchFile {
  /// A row of a comparison of the sides of a patch that stands for a run of lines the patch
  /// passes over.
  public struct GapRow: Sendable, Hashable {
    /// The row of the grid, where the placeholder lines of both sides stand.
    public let row: Int

    /// The number of lines that the run passes over.
    public let lineCount: Int
  }

  /// The rows of the grid of a comparison of `files`, the two sides of a file of a patch, where
  /// their placeholder lines stand side by side; none unless both files are such sides.
  ///
  /// A placeholder that the comparison does not pair up with its counterpart has no row; the
  /// numbers of the lines around it still show that lines are missing.
  static func gapRows(of files: Session.Inputs<ComparedFile>, on layout: RowLayout) -> [GapRow] {
    guard let a = files.a.file.patchSide, let b = files.b.file.patchSide else { return [] }
    return zip(a.placeholders, b.placeholders).compactMap { placeholderA, placeholderB in
      guard let lineA = a.line(ofPatchLine: placeholderA.line, in: files.a),
        let lineB = b.line(ofPatchLine: placeholderB.line, in: files.b)
      else { return nil }
      let row = layout.row(ofLine: lineA, in: .a)
      guard row == layout.row(ofLine: lineB, in: .b), layout.block(atRow: row).kind == .unchanged
      else { return nil }
      return GapRow(row: row, lineCount: max(placeholderA.lineCount, placeholderB.lineCount))
    }
  }
}

extension PatchFile.Side {
  /// The number in its file of each line of `file`, which holds this side as a comparison split
  /// it, counted from 0.
  ///
  /// A comparison may split a line of the patch into several, as it does with a file whose lines
  /// end in CR alone, which Git takes for a single line; each of them takes the next number, as
  /// they would in the file.
  func lineNumbers(of file: ComparedFile) -> [Int32] {
    let starts = file.text.lineStarts
    var numbers: [Int32] = []
    numbers.reserveCapacity(starts.lineCount)
    var patchLine = -1
    var linesBefore = 0
    for line in 0..<starts.lineCount {
      let previous = patchLine
      while patchLine + 1 < lineStarts.count, lineStarts[patchLine + 1] <= starts[line] {
        patchLine += 1
      }
      linesBefore = patchLine == previous ? linesBefore + 1 : 0
      numbers.append(patchLine < 0 ? Int32(line) : lineNumbers[patchLine] + Int32(linesBefore))
    }
    return numbers
  }

  /// The line of `file`, which holds this side as a comparison split it, that starts where the
  /// line `patchLine` of the patch starts, or `nil` if none does.
  fileprivate func line(ofPatchLine patchLine: Int, in file: ComparedFile) -> Int? {
    let starts = file.text.lineStarts
    guard patchLine < lineStarts.count, starts.lineCount > 0 else { return nil }
    let line = starts.line(containing: lineStarts[patchLine])
    return starts[line] == lineStarts[patchLine] ? line : nil
  }
}

extension Session {
  /// The number each line of the input of `role` has in its file, counted from 0, where the
  /// input is a side of a patch and its lines keep the numbers the hunks give them; `nil` for an
  /// input whose lines are numbered by their place, or one that does not take part.
  public func lineNumbers(in role: Role) -> [Int32]? {
    guard let file = files[role], let side = file.file.patchSide else { return nil }
    return side.lineNumbers(of: file)
  }

  /// The line of the input of `role` whose number, as ``lineNumbers(in:)`` gives it, is the
  /// first at or after `number`, so that Go to Line finds a line of a side of a patch by the
  /// number it shows; `number` itself for an input numbered by its places.
  public func line(numbered number: Int, in role: Role) -> Int {
    guard let numbers = lineNumbers(in: role), !numbers.isEmpty else { return number }
    return min(numbers.partitioningIndex { Int($0) >= number }, numbers.count - 1)
  }
}
