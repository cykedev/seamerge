import AppKit
import MergeModel
import Testing

@testable import PaneKit
@testable import SeamergeUI

/// Draws the pictures of the margins of a window for the visual review: the signs of blocks on
/// one boundary beside a short file with its overview bars, and the sign that collapses an
/// expanded run, each in every look, without color, with reduced transparency and in the
/// smallest window.
@MainActor
@Suite(.serialized) struct MarginPicturesTests {
  /// The settings that each picture is drawn with besides the four looks.
  static let settings: [(name: String, look: Look, options: DisplayOptions, size: CGSize?)] =
    Look.all.map { look in
      (
        look.name, look, DisplayOptions(increasesContrast: look.increasesContrast),
        WindowMetrics.defaultContentSize
      )
    } + [
      (
        "without-color-light", .light, DisplayOptions(differentiatesWithoutColor: true),
        WindowMetrics.defaultContentSize
      ),
      (
        "without-color-dark", .dark, DisplayOptions(differentiatesWithoutColor: true),
        WindowMetrics.defaultContentSize
      ),
      (
        "reduced-transparency-light", .light, DisplayOptions(reducesTransparency: true),
        WindowMetrics.defaultContentSize
      ),
      ("smallest-light", .light, DisplayOptions(), nil),
    ]

  @Test func signsOnOneBoundaryBesideAShortFileArePictured() async throws {
    let session = try await Self.deletionsAtBoundaries()
    for setting in Self.settings {
      try Windows.picture(
        session, context: SessionContext(), look: setting.look, options: setting.options,
        size: setting.size, named: "signs-apart-\(setting.name)")
    }
  }

  @Test func signThatCollapsesAnExpandedRunIsPictured() async throws {
    let session = try await SampleMerges.manyBlocks(lineCount: 600, spacing: 30)
    for setting in Self.settings {
      try Windows.picture(
        session, context: SessionContext(), look: setting.look, options: setting.options,
        size: setting.size, named: "collapse-sign-\(setting.name)"
      ) { controller in
        let pane = controller.layout.sourcePanes[0].pane
        guard let run = pane.collapsedRuns.first else { return }
        controller.presentation.pane(pane, didAskToExpand: run)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let row = run.rows.lowerBound + 1
        pane.gutterView.pointerMoved(
          to: CGPoint(x: 4, y: (CGFloat(row) + 0.5) * pane.theme.rowHeight - pane.scrollOrigin.y))
      }
    }
  }

  /// The merge of the user's first test: blocks that both sides deleted lie on the boundaries
  /// beside blocks of one row, at the start of the file and after line 8.
  private static func deletionsAtBoundaries() async throws -> Session {
    let a = """
      // This is a multi-line comment
      class HelloWorld0
      {
          // This is a single-line comment
          public static void main(String[] argList)
          {
              System.out.println("Hello World");
          }
      }

      """
    let base = """
      /*
         multi-line comment
      */
      class HelloWorld1
      {
          // single-line comment
          public satic void main(String[] args)
          {
              System.out.println("Hello Java!");
              System.out.println("Hello Java!");
              System.out.println("Hello Java!");
          }
      }

      """
    let b = """
      // This is a multi-line comment
      class HelloWorld0
      {
          // This is a single-line comment
          public static void main(String args[])
          {
              System.out.println("Hello World");
          }
      }

      """
    return try await SampleMerges.merge(base: base, a: a, b: b)
  }
}
