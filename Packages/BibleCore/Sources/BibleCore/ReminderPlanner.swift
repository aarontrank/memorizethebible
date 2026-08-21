import Foundation

/// The reminder rule from §10, as pure date arithmetic and copy.
///
/// Kept out of the app target so the 24-hour inactivity rule can be tested
/// against `TestClock` rather than by leaving a phone alone overnight (M8).
/// The `UNUserNotificationCenter` plumbing stays in the app.
public enum ReminderPlanner {
    /// §10: after a full day of inactivity, clamped to the user's chosen time
    /// of day.
    ///
    /// "A full day" is the floor, not the target: firing at the chosen time
    /// *before* 24 hours have passed would nag a user who opened the app this
    /// morning, so the first occurrence of the reminder time at or after
    /// `now + 24h` is used.
    public static func nextFireDate(after now: Date, at time: ReminderTime, calendar: Calendar) -> Date? {
        guard let earliest = calendar.date(byAdding: .hour, value: 24, to: now) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: earliest)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate >= earliest { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    /// §10: quiet and non-nagging, with the live psalm and verse pulled from
    /// progress at schedule time.
    public static func message(
        progress: ProgressSnapshot,
        content: ContentStore,
        clock: any AppClock
    ) -> String {
        let report = ProgressReport(content: content, clock: clock)

        switch progress.currentTarget {
        case let .chapter(ref):
            let title = content.title(for: ref)
            let chapter = report.chapterProgress(ref, in: progress)
            guard chapter.unitCount > 0 else { return "\(title) is waiting." }
            let noun = chapter.unitCount == 1 ? "verse" : "verses"
            return "\(title) is waiting — \(chapter.masteredCount) of \(chapter.unitCount) \(noun)."
        case let .plan(id):
            guard let plan = report.plan(id: id, in: progress) else { return "A plan is waiting." }
            let planProgress = report.planProgress(plan, in: progress)
            guard planProgress.unitCount > 0 else { return "\(plan.title) is waiting." }
            let noun = planProgress.unitCount == 1 ? "verse" : "verses"
            return "\(plan.title) — \(planProgress.masteredCount) of \(planProgress.unitCount) \(noun)."
        }
    }
}
