import Foundation
import MergeModel
import PaneKit

/// How the panes of a window show a session, which decides what each of them shows.
struct PaneSetup: Equatable, Sendable {
  /// Which input each pane side by side shows, and whether a result stands below them.
  var arrangement: PaneArrangement

  /// Whether the panes side by side line up their lines on the grid.
  var alignsLines: Bool

  /// Whether the pane of the base is in view.
  var baseIsShown: Bool

  /// Whether the panes highlight the places where their lines differ in a way that the
  /// comparison mode ignores.
  var showsIgnoredChanges: Bool

  /// The side that the single column shows first while it shows, or `nil` while the panes side
  /// by side show.
  var columnFirstSide: Role?

  /// The inputs on the left and on the right of each seam in view, from left to right.
  var seams: [Seam]

  /// The headers of the inputs, whose names the decision column of a merge uses; none for a
  /// comparison, which has no such column.
  var headers: [Role: SideHeader]

  /// The width of a tab in the panes, in columns.
  var tabWidth: Int

  /// The inputs on both sides of a seam.
  struct Seam: Hashable, Sendable {
    var left: Role
    var right: Role
  }
}

/// What the panes of a window show for a session, made away from the main actor, so that the
/// window only puts it in place: the content and the collapsed runs of each pane, the marks of
/// the overview bars, the bands of the seams and, in a merge, the result and the decision column.
struct PreparedSession: Sendable {
  /// The content of a pane side by side.
  struct SourcePane: Sendable {
    var role: Role
    var content: PaneContent
    var prepared: PreparedPaneContent?
    var collapsedRuns: [CollapsedRun]
  }

  /// What the single column shows.
  struct Column: Sendable {
    var layout: SingleColumnLayout
    var content: PaneContent
    var prepared: PreparedPaneContent?
    var collapsedRuns: [CollapsedRun]
    var marks: [OverviewMark]
  }

  /// What the result pane and the decision column show.
  struct Result: Sendable {
    var content: ResultPaneContent
    var prepared: PreparedPaneContent?
    var collapsedRuns: [CollapsedRun]
    var marks: [OverviewMark]
  }

  /// How the panes show the session, which the contents were made for.
  let setup: PaneSetup

  /// The changed blocks of the session.
  let changes: SessionChanges

  /// The session, with its result if it is a merge.
  let shown: ShownSession

  /// The runs of unchanged rows, all collapsed that collapse in a new window.
  let collapsed: CollapsedRows

  /// The lines that differ in a way that the comparison mode ignores.
  let ignoredDifferences: IgnoredDifferences

  /// The lines of the inputs without filler rows, as far as the contents needed them.
  let lines: InputLines

  /// The panes side by side, from left to right.
  let sources: [SourcePane]

  /// The marks of the overview bar beside the panes side by side.
  let sourceMarks: [OverviewMark]

  /// The blocks each seam in view draws no band for.
  let blocksWithoutBand: [PaneSetup.Seam: IndexSet]

  /// What the single column shows, while it shows.
  let column: Column?

  /// What the result pane shows, in a merge.
  let resultPane: Result?

  /// Whether a pane side by side has a place where its lines differ in a way that the
  /// comparison mode ignores, if that was worked out beforehand.
  let hasPlacesOfIgnoredChanges: Bool?

  /// Prepares what the panes show for `shown`, as `setup` says, with the runs of `collapsed`, or
  /// with every run collapsed that collapses in a new window; `lines` are the lines worked out
  /// for a former comparison, of which those of files that stayed the same are kept.
  ///
  /// - Precondition: `collapsed` holds the runs of the session.
  init(
    _ shown: ShownSession, setup: PaneSetup, lines: InputLines, collapsed: CollapsedRows? = nil
  ) {
    let basis = Basis(
      shown: shown, setup: setup, lines: lines, collapsed: collapsed, preparesPanes: false)
    var lines = basis.lines
    let sources = setup.arrangement.sourceRoles.map { basis.sourcePane(of: $0, lines: &lines) }
    let column = basis.column(lines: &lines)
    self.init(
      basis: basis, lines: lines, sources: sources, sourceMarks: basis.sourceMarks(),
      column: column, resultPane: basis.resultPane(), hasPlacesOfIgnoredChanges: nil)
  }

  /// Prepares what the panes show as ``init(_:setup:lines:collapsed:)`` does, and makes the
  /// panes, the marks and the result at the same time, each pane with what showing it takes
  /// worked out.
  @concurrent
  static func concurrently(
    _ shown: ShownSession, setup: PaneSetup, lines: InputLines, collapsed: CollapsedRows? = nil
  ) async -> PreparedSession {
    let basis = Basis(
      shown: shown, setup: setup, lines: lines, collapsed: collapsed, preparesPanes: true)
    let sources = await withTaskGroup(of: (SourcePane, InputLines).self) { group in
      for role in setup.arrangement.sourceRoles {
        group.addTask {
          var lines = basis.lines
          return (basis.sourcePane(of: role, lines: &lines), lines)
        }
      }
      var panes: [(SourcePane, InputLines)] = []
      for await pane in group {
        panes.append(pane)
      }
      return panes
    }
    async let sourceMarks = basis.sourceMarks()
    async let resultPane = basis.resultPane()
    async let hasPlacesOfIgnoredChanges = basis.hasPlacesOfIgnoredChanges()
    var lines = basis.lines
    for (_, paneLines) in sources {
      lines.take(paneLines)
    }
    let column = basis.column(lines: &lines)
    return await PreparedSession(
      basis: basis, lines: lines,
      sources: setup.arrangement.sourceRoles.compactMap { role in
        sources.first { $0.0.role == role }?.0
      },
      sourceMarks: sourceMarks, column: column, resultPane: resultPane,
      hasPlacesOfIgnoredChanges: hasPlacesOfIgnoredChanges)
  }

  private init(
    basis: Basis, lines: InputLines, sources: [SourcePane], sourceMarks: [OverviewMark],
    column: Column?, resultPane: Result?, hasPlacesOfIgnoredChanges: Bool?
  ) {
    setup = basis.setup
    changes = basis.changes
    shown = basis.shown
    collapsed = basis.collapsed
    ignoredDifferences = basis.ignoredDifferences
    self.lines = lines
    self.sources = sources
    self.sourceMarks = sourceMarks
    blocksWithoutBand = Dictionary(
      basis.setup.seams.map {
        ($0, basis.changes.blocksWithoutDifference(between: $0.left, and: $0.right))
      },
      uniquingKeysWith: { first, _ in first })
    self.column = column
    self.resultPane = resultPane
    self.hasPlacesOfIgnoredChanges = hasPlacesOfIgnoredChanges
  }

  /// What every pane of a prepared session is made from.
  private struct Basis: Sendable {
    let shown: ShownSession
    let setup: PaneSetup
    let changes: SessionChanges
    let collapsed: CollapsedRows
    let ignoredDifferences: IgnoredDifferences
    let lines: InputLines

    /// Whether the contents of the panes come with what showing them takes worked out.
    let preparesPanes: Bool

    var session: Session { shown.session }

    var result: ResultState? { shown.result }

    init(
      shown: ShownSession, setup: PaneSetup, lines: InputLines, collapsed: CollapsedRows?,
      preparesPanes: Bool
    ) {
      precondition(
        (shown.result != nil) == setup.arrangement.showsResult,
        "A merge shows its result below the inputs, a comparison nothing")
      let session = shown.session
      self.shown = shown
      self.setup = setup
      changes = SessionChanges(session: session, origin: setup.arrangement.origin)
      self.collapsed =
        collapsed ?? CollapsedRows(session: session, document: shown.result?.document)
      ignoredDifferences = IgnoredDifferences(in: session)
      self.lines = lines.carried(to: session)
      self.preparesPanes = preparesPanes
    }

    /// `content` with what showing it takes worked out, if the panes are prepared.
    func prepared(_ content: PaneContent) -> PreparedPaneContent? {
      preparesPanes ? PreparedPaneContent(preparing: content, tabWidth: setup.tabWidth) : nil
    }

    func sourcePane(of role: Role, lines: inout InputLines) -> SourcePane {
      let content = PreparedSession.sourceContent(
        of: role, setup: setup, changes: changes, document: result?.document,
        ignoredDifferences: ignoredDifferences, lines: &lines)
      return SourcePane(
        role: role, content: content, prepared: prepared(content),
        collapsedRuns: PreparedSession.sourceRuns(
          of: collapsed.runs, in: role, collapsed: collapsed, alignsLines: setup.alignsLines))
    }

    func sourceMarks() -> [OverviewMark] {
      OverviewMarks.sources(
        of: changes, document: result?.document, arrangement: setup.arrangement,
        baseIsShown: setup.baseIsShown)
    }

    func column(lines: inout InputLines) -> Column? {
      setup.columnFirstSide.map { firstSide in
        var column = PreparedSession.column(
          SingleColumnLayout(session: session, firstSide: firstSide), changes: changes,
          collapsed: collapsed, ignoredDifferences: ignoredDifferences,
          showsIgnoredPlaces: setup.showsIgnoredChanges, lines: &lines)
        column.prepared = prepared(column.content)
        return column
      }
    }

    func hasPlacesOfIgnoredChanges() -> Bool {
      PreparedSession.hasPlaces(
        of: ignoredDifferences, in: setup.arrangement.sourceRoles, of: session)
    }

    func resultPane() -> Result? {
      result.map { result in
        let content = ResultPaneContent(result: result, changes: changes, headers: setup.headers)
        return Result(
          content: content, prepared: prepared(content.content),
          collapsedRuns: PreparedSession.resultRuns(
            of: collapsed.runs, collapsed: collapsed, result: result),
          marks: OverviewMarks.result(
            of: changes, document: result.document, result: content.content))
      }
    }
  }

  /// The content of the pane of `role`, on the grid or with the lines of its file as `setup`
  /// says.
  static func sourceContent(
    of role: Role, setup: PaneSetup, changes: SessionChanges, document: ResultDocument?,
    ignoredDifferences: IgnoredDifferences, lines: inout InputLines
  ) -> PaneContent {
    setup.alignsLines
      ? PaneContent(
        source: role, of: changes, lineEndings: lines.endings(of: role), document: document,
        ignoredDifferences: ignoredDifferences, showsIgnoredPlaces: setup.showsIgnoredChanges,
        baseIsShown: setup.baseIsShown)
      : PaneContent(
        lines: role, text: lines.text(of: role), of: changes,
        lineEndings: lines.endings(of: role), document: document,
        ignoredDifferences: ignoredDifferences, showsIgnoredPlaces: setup.showsIgnoredChanges,
        baseIsShown: setup.baseIsShown)
  }

  /// What the single column shows with `layout`.
  static func column(
    _ layout: SingleColumnLayout, changes: SessionChanges, collapsed: CollapsedRows,
    ignoredDifferences: IgnoredDifferences, showsIgnoredPlaces: Bool, lines: inout InputLines
  ) -> Column {
    Column(
      layout: layout,
      content: PaneContent(
        column: layout, of: changes,
        lineEndings: Session.Inputs(a: lines.endings(of: .a), b: lines.endings(of: .b)),
        ignoredDifferences: ignoredDifferences, showsIgnoredPlaces: showsIgnoredPlaces),
      collapsedRuns: columnRuns(of: collapsed.runs, in: layout, collapsed: collapsed),
      marks: OverviewMarks.column(of: changes, column: layout))
  }

  /// Whether the input of one of `roles` has a place where its lines differ in a way that the
  /// comparison mode ignores, as `ignoredDifferences` of `session` tell; a place that cannot be
  /// worked out counts as none.
  static func hasPlaces(
    of ignoredDifferences: IgnoredDifferences, in roles: [Role], of session: Session
  ) -> Bool {
    guard !ignoredDifferences.isEmpty else { return false }
    return roles.contains { role in
      do {
        return try !ignoredDifferences.places(in: role, of: session).isEmpty
      } catch {
        return false
      }
    }
  }

  /// `runs` in the rows of the pane of `role`: rows of the grid, or lines of its file.
  static func sourceRuns(
    of runs: [CollapsedRows.Run], in role: Role, collapsed: CollapsedRows, alignsLines: Bool
  ) -> [CollapsedRun] {
    runs.map { CollapsedRun(rows: alignsLines ? $0.rows : collapsed.lines(of: $0, in: role)) }
  }

  /// `runs` in the rows of `column`.
  static func columnRuns(
    of runs: [CollapsedRows.Run], in column: SingleColumnLayout, collapsed: CollapsedRows
  ) -> [CollapsedRun] {
    runs.map { CollapsedRun(rows: collapsed.rows(of: $0, in: column)) }
  }

  /// `runs` in lines of `result`, without those that hide no line there.
  static func resultRuns(
    of runs: [CollapsedRows.Run], collapsed: CollapsedRows, result: ResultState
  ) -> [CollapsedRun] {
    runs.compactMap { run in
      let lines = collapsed.resultLines(of: run, in: result.scrollMap)
      return lines.isEmpty ? nil : CollapsedRun(rows: lines)
    }
  }
}
