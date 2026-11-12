import Foundation
import MergeModel
import Testing

struct FileEncodingTests {
  @Test func fileTellsTheEncodingItWasReadIn() {
    let utf8 = SourceFile(bytes: Data("caf\u{E9}\n".utf8), label: "utf8")
    #expect(utf8.encoding == .utf8)

    let utf16 = SourceFile(bytes: Data([0xFF, 0xFE, 0x61, 0x00, 0x0A, 0x00]), label: "utf16")
    #expect(utf16.encoding == .utf16LittleEndian)

    // Curly quotes, a dash and the euro sign exist in Windows-1252 alone.
    let text = "\u{201C}Gr\u{FC}\u{DF}e\u{201D} \u{2013} 5 \u{20AC}\n"
    let windows = SourceFile(
      bytes: text.data(using: .windowsCP1252) ?? Data(), label: "windows")
    #expect(windows.encoding == .windows1252)
  }

  @Test func binaryFileHasNoEncoding() {
    let binary = SourceFile(bytes: Data([0x00, 0x01, 0x02, 0x00]), label: "binary")
    #expect(binary.isBinary)
    #expect(binary.encoding == nil)
  }
}
