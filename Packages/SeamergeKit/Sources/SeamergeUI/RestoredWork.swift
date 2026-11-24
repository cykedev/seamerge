import Foundation

/// Earlier work that a merge window put back as it opened, which its subtitle names until the
/// user takes a step of their own.
struct RestoredWork: Equatable {
  /// When the work was captured.
  let savedAt: Date

  /// The number of blocks that start as loaded, because the comparison has no block with the
  /// same lines; 0 when every decision and every text typed by hand is back.
  let restartedBlockCount: Int

  /// What the subtitle says: that the work is back, or partly, and from when: the time for work
  /// of the day `now` falls on, else the date, with the year only for another year.
  func note(now: Date, calendar: Calendar, locale: Locale) -> String {
    var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    if calendar.isDate(savedAt, inSameDayAs: now) {
      style = style.hour().minute()
    } else if calendar.isDate(savedAt, equalTo: now, toGranularity: .year) {
      style = style.month(.abbreviated).day()
    } else {
      style = style.month(.abbreviated).day().year()
    }
    let time = savedAt.formatted(style)
    return restartedBlockCount == 0
      ? String(
        localized: "Earlier work restored · \(time)", bundle: .module,
        comment:
          "Subtitle: the window put back the work of an earlier session of the same merge, such as Earlier work restored · 14:32 or · Nov 21."
      )
      : String(
        localized: "Earlier work partly restored · \(time)", bundle: .module,
        comment:
          "Subtitle: the window put back some of the work of an earlier session of the same merge, such as Earlier work partly restored · 14:32."
      )
  }

  /// What VoiceOver hears as the window opens with the work: how many conflicts are resolved,
  /// of `conflictCount` with `openConflictCount` open, or how many blocks start over.
  func announcement(conflictCount: Int, openConflictCount: Int) -> String {
    if restartedBlockCount > 0 {
      return String(
        localized: "Earlier work partly restored: \(restartedBlockCount) blocks start over.",
        bundle: .module,
        comment:
          "VoiceOver as a merge opens with some of its earlier work, such as 2 blocks start over.")
    }
    guard conflictCount > 0 else {
      return String(
        localized: "Earlier work restored.", bundle: .module,
        comment: "VoiceOver as a merge without conflicts opens with its earlier work.")
    }
    return String(
      localized:
        "Earlier work restored: \(conflictCount - openConflictCount) of \(conflictCount) conflicts resolved.",
      bundle: .module,
      comment:
        "VoiceOver as a merge opens with its earlier work, such as 3 of 5 conflicts resolved.")
  }

  /// What Undo calls putting the earlier work back.
  static var undoName: String {
    String(
      localized: "Restore Earlier Work", bundle: .module,
      comment: "Undo menu: the work of an earlier session of the same merge was put back.")
  }
}
