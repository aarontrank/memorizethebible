import Foundation
import Observation
import BibleCore

/// The app's single source of truth: bundled scripture, on-device progress, and
/// the clock everything else reads (§14).
@Observable
@MainActor
final class AppState {
    private(set) var content: ContentStore
    private(set) var progress: ProgressSnapshot
    /// Non-nil when content or progress could not be loaded; surfaced instead
    /// of crashing.
    private(set) var loadError: String?

    let clock: any AppClock
    private let store: ProgressStore
    private let reminders: ReminderScheduler

    init(
        content: ContentStore,
        store: ProgressStore,
        clock: any AppClock = SystemClock(),
        reminders: ReminderScheduler = ReminderScheduler()
    ) {
        self.content = content
        self.store = store
        self.clock = clock
        self.reminders = reminders
        self.progress = store.load()
    }

    /// The shipping configuration.
    static func live(clock: any AppClock = SystemClock()) -> AppState {
        do {
            let content = try ContentStore(source: BundleContentSource())
            #if DEBUG
                if DebugLaunch.isActive {
                    return debugState(content: content, clock: clock)
                }
            #endif
            let store = ProgressStore(fileURL: try ProgressStore.defaultFileURL(), clock: clock)
            return AppState(content: content, store: store, clock: clock)
        } catch {
            return AppState(failedWith: error)
        }
    }

    #if DEBUG
        /// Debug builds only: a throwaway progress file seeded to a chosen step.
        private static func debugState(content: ContentStore, clock: any AppClock) -> AppState {
            let url = DebugLaunch.progressFileURL()
            try? FileManager.default.removeItem(at: url)
            let store = ProgressStore(fileURL: url, clock: clock)
            let state = AppState(content: content, store: store, clock: clock)
            if let seeded = DebugLaunch.seededProgress(content: content, clock: clock) {
                state.apply(seeded)
            }
            return state
        }
    #endif

    private init(failedWith error: Error) {
        let empty = ContentManifest(
            schemaVersion: 2,
            translationId: "bsb",
            name: "Berean Standard Bible",
            attributionNotice: "",
            longChapterVerseThreshold: SessionRules.longChapterVerseThreshold,
            bookCount: 0,
            chapterCount: 0,
            verseCount: 0,
            books: []
        )
        content = ContentStore(manifest: empty)
        store = ProgressStore(fileURL: URL(fileURLWithPath: "/dev/null"))
        clock = SystemClock()
        reminders = ReminderScheduler()
        progress = ProgressSnapshot()
        loadError = error.localizedDescription
    }

    // MARK: - Derived

    var report: ProgressReport { ProgressReport(content: content, clock: clock) }
    var overall: OverallProgress { report.overall(in: progress) }

    func chapterProgress(_ ref: ChapterRef) -> ChapterProgress {
        report.chapterProgress(ref, in: progress)
    }

    func bookProgress(_ id: BookID) -> BookProgress { report.bookProgress(id, in: progress) }

    func planProgress(_ plan: MemoryPlan) -> PlanProgress { report.planProgress(plan, in: progress) }

    var plans: [MemoryPlan] { report.plans(in: progress) }

    func plan(id: String) -> MemoryPlan? { report.plan(id: id, in: progress) }

    func chapter(_ ref: ChapterRef) -> Chapter? {
        do { return try content.chapter(ref) } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    func title(for ref: ChapterRef) -> String { content.title(for: ref) }

    // MARK: - Display

    /// The verses a target covers, grouped by chapter for display. A plan shows
    /// only its own verses: the plan is the context there, not the chapter.
    func sections(for target: MemoryTarget) -> [ScriptureSection] {
        if let chapterRef = target.chapterRef { return wholeChapterSections(chapterRef) }
        var sections: [ScriptureSection] = []
        for chapterRef in target.chapterRefs {
            guard let chapter = chapter(chapterRef) else { continue }
            let wanted = Set(target.units.filter { $0.chapterRef == chapterRef }.map(\.verse))
            sections.append(
                ScriptureSection(
                    ref: chapterRef,
                    title: title(for: chapterRef),
                    superscription: wanted.contains(0) ? chapter.superscription : nil,
                    verses: chapter.verses.filter { wanted.contains($0.number) }
                )
            )
        }
        return sections
    }

    /// The whole chapter, so a chapter session always shows its context (§8.2).
    func wholeChapterSections(_ ref: ChapterRef) -> [ScriptureSection] {
        guard let chapter = chapter(ref) else { return [] }
        return [
            ScriptureSection(
                ref: ref,
                title: title(for: ref),
                superscription: chapter.superscription,
                verses: chapter.verses
            )
        ]
    }

    // MARK: - Targets

    func target(forChapter ref: ChapterRef) -> MemoryTarget? {
        guard let chapter = chapter(ref) else { return nil }
        return report.target(for: chapter, in: progress)
    }

    func target(forPlan plan: MemoryPlan) -> MemoryTarget { report.target(for: plan, in: progress) }

    func target(for id: MemoryTargetID) -> MemoryTarget? {
        switch id {
        case let .chapter(ref): return target(forChapter: ref)
        case let .plan(planID): return plan(id: planID).map { target(forPlan: $0) }
        }
    }

    // MARK: - Mutations

    func apply(_ snapshot: ProgressSnapshot) {
        progress = snapshot
        persist()
    }

    func mutate(_ body: (inout ProgressSnapshot) -> Void) {
        body(&progress)
        persist()
    }

    private func persist() {
        do { try store.save(progress) } catch { loadError = error.localizedDescription }
    }

    // MARK: - Plans

    func addPlan(_ plan: MemoryPlan) {
        mutate { snapshot in
            snapshot.customPlans.removeAll { $0.id == plan.id }
            snapshot.customPlans.append(plan)
        }
    }

    func updatePlan(_ plan: MemoryPlan) {
        mutate { snapshot in
            guard let index = snapshot.customPlans.firstIndex(where: { $0.id == plan.id }) else { return }
            snapshot.customPlans[index] = plan
        }
    }

    /// Removing a plan removes only the plan. The verses it named stay
    /// memorized, because mastery belongs to the verse, not to the plan.
    func removePlan(_ plan: MemoryPlan) {
        mutate { snapshot in
            if plan.isBuiltIn {
                snapshot.hiddenBuiltInPlans.insert(plan.id)
            } else {
                snapshot.customPlans.removeAll { $0.id == plan.id }
            }
            snapshot.completedPlans.removeValue(forKey: plan.id)
            snapshot.confirmedPlanBlocks.removeValue(forKey: plan.id)
            snapshot.planCumulativeProgress.removeValue(forKey: plan.id)
            if snapshot.currentTarget == .plan(plan.id) {
                snapshot.currentTarget = .chapter(ChapterRef(.psalms, 1))
            }
        }
    }

    func restoreHiddenPlans() {
        mutate { $0.hiddenBuiltInPlans.removeAll() }
    }

    // MARK: - Lifecycle (§10)

    func didEnterForeground() {
        mutate { $0.lastOpenedAt = clock.now }
        Task { await reminders.reschedule(for: progress, content: content, clock: clock) }
    }

    func didEnterBackground() {
        Task { await reminders.reschedule(for: progress, content: content, clock: clock) }
    }

    // MARK: - Settings (§8.4)

    func setNotificationsEnabled(_ enabled: Bool) async {
        if enabled {
            // §10: permission is requested only here, never at launch.
            guard await reminders.requestAuthorization() else { return }
        }
        mutate { $0.notificationsEnabled = enabled }
        if enabled {
            await reminders.reschedule(for: progress, content: content, clock: clock)
        } else {
            await reminders.cancelAll()
        }
    }

    func setReminderTime(_ time: ReminderTime) {
        mutate { $0.reminderTime = time }
        Task { await reminders.reschedule(for: progress, content: content, clock: clock) }
    }

    /// Psalms that would reopen if headings were switched on (§7.5).
    func chaptersReopenedByIncludingHeadings() -> [ChapterRef] {
        report.chaptersReopenedByIncludingHeadings(in: progress)
    }

    /// §7.5: non-destructive in both directions.
    func setIncludeSuperscriptions(_ include: Bool) {
        apply(report.applyingHeadings(include, to: progress))
    }

    func resetProgress() {
        do {
            progress = try store.reset()
        } catch {
            loadError = error.localizedDescription
        }
        Task { await reminders.cancelAll() }
    }
}
