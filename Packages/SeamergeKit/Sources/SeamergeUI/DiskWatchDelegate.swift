/// Tells a watch of files on disk whether the window can reload them, and reloads them.
@MainActor
protocol DiskWatchDelegate: AnyObject {
  /// Whether the window can reload its files now, works with them, or has none to reload.
  func readinessToReload(for watch: DiskWatch) -> DiskWatch.Readiness

  /// Reloads what changed on disk; the watch asks again for no reload until this returns.
  func reloadChangedFiles(for watch: DiskWatch) async
}
