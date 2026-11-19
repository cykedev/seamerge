import AppKit
public import Foundation
import MergeModel
import os

/// A merge of a file that is not text, such as an image, which Seamerge cannot merge line by
/// line: its window offers to take one side as a whole, or to leave the file unresolved.
public struct BinaryMerge: Sendable {
  /// The incoming side.
  public let a: SessionFile

  /// The own side.
  public let b: SessionFile

  /// The file that Git reads the result from.
  public let output: URL

  /// Describes the merge of `a` and `b` into `output`.
  public init(a: SessionFile, b: SessionFile, output: URL) {
    self.a = a
    self.b = b
    self.output = output
  }

  /// A comparison of the two sides without their contents, which gives the window its headers.
  ///
  /// - Throws: ``SessionLoadingError/comparisonFailed`` if even that fails.
  func emptySession() async throws(SessionLoadingError) -> Session {
    do {
      return try await Session.diff(
        old: SourceFile(bytes: Data(), label: a.label),
        new: SourceFile(bytes: Data(), label: b.label), mode: .windowDefault)
    } catch {
      throw .comparisonFailed
    }
  }

  /// The name of the file as the window and its sheet show it.
  var name: String {
    output.lastPathComponent
  }

  /// Writes the bytes of the file of `role`, A or B, to ``output``.
  ///
  /// The output is replaced atomically, so that a failure leaves it as it was, and keeps its
  /// permissions.
  ///
  /// - Throws: The error of the file system if the side cannot be read or the output cannot be
  ///   written.
  func take(_ role: Role) throws {
    let source = role == .a ? a.url : b.url
    let fileManager = FileManager.default
    let destination = output.resolvingSymlinksInPath()
    let scratch = try fileManager.url(
      for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination,
      create: true)
    defer { removeScratch(scratch) }
    let copy = scratch.appending(path: destination.lastPathComponent)
    try fileManager.copyItem(at: source, to: copy)
    if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
      let permissions = try fileManager.attributesOfItem(
        atPath: destination.path(percentEncoded: false))[.posixPermissions]
      if let permissions {
        try fileManager.setAttributes(
          [.posixPermissions: permissions], ofItemAtPath: copy.path(percentEncoded: false))
      }
      _ = try fileManager.replaceItemAt(destination, withItemAt: copy)
    } else {
      try fileManager.moveItem(at: copy, to: destination)
    }
  }

  private func removeScratch(_ scratch: URL) {
    do {
      try FileManager.default.removeItem(at: scratch)
    } catch {
      Logger(subsystem: "app.eiden.seamerge", category: "SeamergeUI").error(
        "Could not remove \(scratch.path, privacy: .public): \(error, privacy: .public)")
    }
  }
}

extension BinaryMerge {
  /// What the window says first: that the file is not text.
  var title: String {
    String(
      localized: "“\(name)” is a binary file.", bundle: .module,
      comment: "Merge of a file that is not text, such as “logo.png” is a binary file.")
  }

  /// What the window and its sheet say below the title: what Seamerge cannot do, and what the
  /// user can.
  static var message: String {
    String(
      localized:
        "Seamerge can’t merge the contents of this file. Use one side as a whole, or leave it unresolved.",
      bundle: .module, comment: "Merge of a file that is not text: what can be done.")
  }
}

extension SessionWindowController {
  /// Shows the window, and for the merge of a file that is not text the sheet that asks which
  /// side to take.
  public override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    guard binaryMerge != nil, !isAskingToClose, !hasFinished else { return }
    Task { await askWhichSideToTake() }
  }

  /// Asks which side of the binary file to take as a whole and writes it, which reports the
  /// session as saved, or leaves the file unresolved; asks again after writing failed.
  func askWhichSideToTake() async {
    guard let merge = binaryMerge, let window else { return }
    isAskingToClose = true
    defer { isAskingToClose = false }
    let headers = presentation.headers
    while !hasFinished {
      let choice = await prompts.chooseSide(
        ofBinaryFile: merge.name, a: headers[.a]?.distinctName ?? Role.a.letter,
        b: headers[.b]?.distinctName ?? Role.b.letter, in: window)
      guard let role = choice else {
        cancel()
        return
      }
      do {
        try merge.take(role)
      } catch {
        await prompts.reportFailedSaving(
          merge.name, reason: error.localizedDescription, in: window)
        continue
      }
      finish(.saved)
      close()
    }
  }
}
