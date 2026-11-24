import AppKit
import MergeModel
import Testing

@testable import SeamergeUI

/// Draws the pictures of text pasted from the clipboard for the visual review: the field that
/// holds it in the sheet Compare Files, and the window that compares it with a file, in every
/// look.
@MainActor
@Suite(.serialized) struct PastedTextPicturesTests {
  /// A configuration copied from a web page, and the file it is compared with.
  private static let pasted = """
    [server]
    host = "0.0.0.0"
    port = 8080
    timeout = 30

    [logging]
    level = "info"
    format = "json"
    """ + "\n"

  private static let file = """
    [server]
    host = "127.0.0.1"
    port = 8080

    [logging]
    level = "debug"
    """ + "\n"

  @Test(arguments: Look.all)
  func fieldWithTextFromTheClipboardIsPictured(look: Look) throws {
    let fixture = try WelcomeFixture(
      displayOptions: DisplayOptions(increasesContrast: look.increasesContrast))
    fixture.clipboard.copy(Self.pasted)
    fixture.controller.paste(nil)
    let folder = URL(filePath: NSHomeDirectory()).appending(path: "Projects/app")
    try fixture.sheet().fill([.right: folder.appending(path: "config.toml")])

    try fixture.picture(look: look, named: "sheet-clipboard-\(look.name)")
  }

  @Test func twoTextsFromTheClipboardArePictured() throws {
    let fixture = try WelcomeFixture()
    fixture.clipboard.copy(Self.pasted)
    fixture.controller.paste(nil)
    fixture.clipboard.copy(Self.file)
    let sheet = try fixture.sheet()
    sheet.paste(nil)

    try fixture.picture(look: .light, named: "sheet-clipboard-both-light")
  }

  @Test(arguments: Look.all)
  func windowOfTextFromTheClipboardIsPictured(look: Look) async throws {
    try await picture(
      look: look, options: DisplayOptions(increasesContrast: look.increasesContrast),
      named: "window-clipboard-\(look.name)")
  }

  @Test func windowOfTextFromTheClipboardIsPicturedWithTheOtherSettings() async throws {
    try await picture(
      look: .light, options: DisplayOptions(differentiatesWithoutColor: true),
      named: "window-clipboard-without-color-light")
    try await picture(
      look: .light, options: DisplayOptions(reducesTransparency: true),
      named: "window-clipboard-reduced-transparency-light")
    try await picture(
      look: .light, options: DisplayOptions(), size: nil, named: "window-clipboard-smallest-light")
  }

  /// Draws the window that compares the pasted configuration with the file in `look` and
  /// `options`, at `size` or at its least size for `nil`.
  private func picture(
    look: Look, options: DisplayOptions, size: CGSize? = WindowMetrics.defaultContentSize,
    named name: String
  ) async throws {
    let clipboard = Clipboard()
    let files = try SampleFiles()
    let text = try clipboard.cache.keep(
      Self.pasted, pastedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
    let url = files.folder.appending(path: "config.toml")
    try Data(Self.file.utf8).write(to: url)
    let comparison = FileComparison(left: text.url, right: url, pastedTexts: [text.url: text])
    let session = try await Session.loadDiff(
      old: comparison.sessionFile(at: text.url), new: comparison.sessionFile(at: url),
      mode: .windowDefault)
    try Windows.picture(
      session, context: SessionContext(pastedTexts: comparison.pastedTexts), look: look,
      options: options, size: size, named: name)
  }
}
