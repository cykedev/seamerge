import Foundation
import MergeModel
import Testing

@testable import SeamergeUI

/// The encoding of each side: in the header only where it differs, always in the details, and
/// that of B in the header of the result.
@MainActor
@Suite struct HeaderEncodingTests {
  @Test func headerNamesTheEncodingOnlyWhereTheSidesDiffer() async throws {
    let same = try await SampleMerges.helloWorld()
    let header = SideHeader(role: .a, session: same, context: SessionContext())
    #expect(header.differingEncoding == nil)
    #expect(header.details.encoding == .utf8)
    #expect(ResultHeader(session: same, context: SessionContext()).format.encoding == .utf8)

    let windows = "caf\u{E9} \u{20AC}\n".data(using: .windowsCP1252) ?? Data()
    let session = try await Session.merge(
      base: SourceFile(bytes: Data("caf\u{E9}\n".utf8), label: "base.txt"),
      a: SourceFile(bytes: Data("caf\u{E9}!\n".utf8), label: "a.txt"),
      b: SourceFile(bytes: windows, label: "b.txt"))
    let a = SideHeader(role: .a, session: session, context: SessionContext())
    let b = SideHeader(role: .b, session: session, context: SessionContext())
    #expect(a.differingEncoding == .utf8)
    #expect(b.differingEncoding == .windows1252)
    #expect(b.differingEncoding?.name == "Windows 1252")
    #expect(
      ResultHeader(session: session, context: SessionContext()).format.encoding == .windows1252)
  }
}
