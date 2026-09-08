import Foundation

/// Reconciling two copies of the progress record — this device's, and the one
/// iCloud is holding — into a single record (§13.1).
///
/// Three rules, in this order:
///
/// 1. **Work done is never lost.** Verses, chapters, coverage, finished plans:
///    every one of them is unioned, and where two copies disagree about a
///    number the higher one stands. Nothing a person actually did can be taken
///    away by opening the app somewhere else. This is the same instinct as the
///    high-water mark inside `VerseState`, applied across devices.
/// 2. **A choice is whatever was chosen most recently.** Which plans are on the
///    home page, where Continue resumes, the reminder time, psalm headings:
///    those are opinions rather than work, and the copy with the newer
///    `updatedAt` holds the current one. Merging opinions would mean a plan
///    taken off the home page here quietly coming back from there.
/// 3. **Some things belong to the device.** Whether reminders are on rests on a
///    permission granted on one device, and a walkthrough running here is not
///    running there.
///
/// Merging rather than picking a winner is what makes the feature safe to leave
/// on: two devices used offline for a week both keep everything they learned.
public enum ProgressMerge {
    public static func merge(local: ProgressSnapshot, remote: ProgressSnapshot) -> ProgressSnapshot {
        // Distant past on either side means a copy that predates sync, which is
        // exactly the copy whose opinions should give way.
        let newer = remote.updatedAt > local.updatedAt ? remote : local
        var merged = local

        merged.schemaVersion = ProgressSnapshot.currentSchemaVersion
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        merged.lastOpenedAt = max(local.lastOpenedAt, remote.lastOpenedAt)

        // 1. Work done.
        merged.verseStates = combining(local.verseStates, remote.verseStates, mergingVerse)
        merged.chapterStates = combining(local.chapterStates, remote.chapterStates, mergingChapter)
        merged.coveredUnits = combining(local.coveredUnits, remote.coveredUnits) { $0.union($1) }
        merged.confirmedPlanBlocks =
            combining(local.confirmedPlanBlocks, remote.confirmedPlanBlocks) { $0.union($1) }
        merged.planCumulativeProgress =
            combining(local.planCumulativeProgress, remote.planCumulativeProgress) { max($0, $1) }
        // When it was finished, not when the other device heard about it.
        merged.completedPlans = combining(local.completedPlans, remote.completedPlans) { min($0, $1) }
        // Once asked, never again — on any device. Apple's prompt says nothing
        // back about whether it appeared, so the one turn the app takes is the
        // one it has.
        merged.hasAskedForReview = local.hasAskedForReview || remote.hasAskedForReview

        // Plans the user wrote, minus the ones they deleted.
        let tombstones = combining(local.removedPlans, remote.removedPlans) { max($0, $1) }
        let surviving = mergingPlans(
            local: local.customPlans,
            remote: remote.customPlans,
            preferring: newer.customPlans,
            removed: tombstones
        )
        let survivingIDs = Set(surviving.map(\.id))
        merged.customPlans = surviving
        // A tombstone has done its work once nobody is offering the plan back.
        merged.removedPlans = tombstones.filter { !survivingIDs.contains($0.key) }

        // 2. Choices.
        merged.translationId = newer.translationId
        merged.currentTarget = newer.currentTarget
        merged.currentVerse = newer.currentVerse
        merged.activePlans = newer.activePlans
        merged.hiddenBuiltInPlans = newer.hiddenBuiltInPlans
        merged.pendingCelebration = newer.pendingCelebration
        merged.reminderTime = newer.reminderTime
        merged.includeSuperscriptions = newer.includeSuperscriptions
        // A plan that is gone cannot be the one you are working through.
        for id in Array(merged.removedPlans.keys) {
            merged.activePlans.remove(id)
            if merged.currentTarget == .plan(id) {
                merged.currentTarget = .chapter(ChapterRef(.psalms, 1))
                merged.currentVerse = nil
            }
            if merged.pendingCelebration == .plan(id) { merged.pendingCelebration = nil }
        }

        // 3. This device's own.
        merged.notificationsEnabled = local.notificationsEnabled
        merged.onboarding = mergingOnboarding(local.onboarding, remote.onboarding)
        return merged
    }

    // MARK: - Pieces

    /// The furthest either device got with a verse.
    ///
    /// Counts take the higher rather than the sum: two devices that each saw
    /// three reads saw the same three reads offline, and inventing a sixth
    /// would let a verse skip a step it never took.
    static func mergingVerse(_ mine: VerseState, _ theirs: VerseState) -> VerseState {
        var merged = rank(mine.status) >= rank(theirs.status) ? mine : theirs
        merged.highestMaskLevelCleared = max(mine.highestMaskLevelCleared, theirs.highestMaskLevelCleared)
        merged.readCount = max(mine.readCount, theirs.readCount)
        merged.peekCount = max(mine.peekCount, theirs.peekCount)
        merged.masteredAt =
            merged.status == .mastered ? earliest(mine.masteredAt, theirs.masteredAt) : nil
        return merged
    }

    static func mergingChapter(_ mine: ChapterState, _ theirs: ChapterState) -> ChapterState {
        ChapterState(
            fullRecitationConfirmed: mine.fullRecitationConfirmed || theirs.fullRecitationConfirmed,
            confirmedStanzas: mine.confirmedStanzas.union(theirs.confirmedStanzas),
            cumulativeConfirmedThrough: max(
                mine.cumulativeConfirmedThrough,
                theirs.cumulativeConfirmedThrough
            ),
            // When the work began and when it was finished, not when this
            // device found out about either.
            startedAt: earliest(mine.startedAt, theirs.startedAt),
            completedAt: earliest(mine.completedAt, theirs.completedAt)
        )
    }

    /// The tour is running, or not, on this device. Whether it has ever been
    /// offered or finished is about the person, so a new device set up from
    /// iCloud does not walk them through the app a second time.
    static func mergingOnboarding(_ mine: OnboardingState, _ theirs: OnboardingState) -> OnboardingState {
        var merged = mine
        merged.hasBeenOffered = mine.hasBeenOffered || theirs.hasBeenOffered
        merged.hasCompleted = mine.hasCompleted || theirs.hasCompleted
        return merged
    }

    private static func mergingPlans(
        local: [MemoryPlan],
        remote: [MemoryPlan],
        preferring newer: [MemoryPlan],
        removed: [String: Date]
    ) -> [MemoryPlan] {
        let preferred = Dictionary(newer.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var plans: [MemoryPlan] = []
        for plan in local + remote where seen.insert(plan.id).inserted {
            // Edits to a plan held on both devices come from the newer copy;
            // the older device's ordering is what keeps the list steady.
            let chosen = preferred[plan.id] ?? plan
            // A plan deleted after it was written stays deleted. One written
            // again since — the same shared plan arriving a second time — is a
            // new decision, and outlives its own tombstone.
            if let removedAt = removed[plan.id], (chosen.createdAt ?? .distantPast) <= removedAt {
                continue
            }
            plans.append(chosen)
        }
        return plans
    }

    // MARK: - Helpers

    private static func combining<Key: Hashable, Value>(
        _ local: [Key: Value],
        _ remote: [Key: Value],
        _ combine: (Value, Value) -> Value
    ) -> [Key: Value] {
        var merged = local
        for (key, value) in remote {
            merged[key] = merged[key].map { combine($0, value) } ?? value
        }
        return merged
    }

    private static func rank(_ status: VerseState.Status) -> Int {
        switch status {
        case .untouched: return 0
        case .inProgress: return 1
        case .mastered: return 2
        }
    }

    private static func earliest(_ mine: Date?, _ theirs: Date?) -> Date? {
        guard let mine else { return theirs }
        guard let theirs else { return mine }
        return min(mine, theirs)
    }
}
