import Foundation

/// Progress for one chapter (§8.1).
public struct ChapterProgress: Hashable, Sendable, Identifiable {
    public let ref: ChapterRef
    /// Memorizable units, including a psalm heading only when that setting is
    /// on (§7.5).
    public let unitCount: Int
    /// Verses of this chapter memorized anywhere, including inside a plan.
    /// This is the figure lists show: "1 of 31 verses".
    public let masteredCount: Int
    /// Verses worked through *in this chapter*. Completion counts these.
    public let coveredCount: Int
    public let inProgressCount: Int
    public let recitationConfirmed: Bool
    /// Whether the chapter has been opened and worked as a chapter.
    public let isStartedAsChapter: Bool
    public let completedAt: Date?

    public var id: ChapterRef { ref }

    /// §7.1: memorized requires every unit worked here AND the closing
    /// recitation. Verses learned elsewhere still have to be met in the
    /// chapter — kept or redone — before the chapter counts as done.
    public var isMemorized: Bool {
        unitCount > 0 && coveredCount == unitCount && recitationConfirmed
    }

    /// Any progress at all, in any context. Drives "1 of 31 verses" in lists.
    public var isStarted: Bool { masteredCount > 0 || inProgressCount > 0 || isStartedAsChapter }

    /// Verses known from elsewhere but not yet worked in this chapter.
    public var carriedOverCount: Int { max(masteredCount - coveredCount, 0) }

    public var fraction: Double {
        unitCount == 0 ? 0 : Double(masteredCount) / Double(unitCount)
    }
}

/// Progress for one book, summed from its chapters.
public struct BookProgress: Hashable, Sendable, Identifiable {
    public let book: BookID
    public let chapterCount: Int
    public let memorizedChapters: Int
    public let startedChapters: Int
    public let verseCount: Int
    public let masteredVerses: Int

    public var id: BookID { book }
    public var isStarted: Bool { masteredVerses > 0 || startedChapters > 0 }
    public var isComplete: Bool { chapterCount > 0 && memorizedChapters == chapterCount }
    public var fraction: Double {
        verseCount == 0 ? 0 : Double(masteredVerses) / Double(verseCount)
    }
}

/// Progress for one memory plan.
public struct PlanProgress: Hashable, Sendable, Identifiable {
    public let planID: String
    public let unitCount: Int
    /// Verses of this plan memorized anywhere.
    public let masteredCount: Int
    /// Verses worked through inside this plan.
    public let coveredCount: Int
    public let inProgressCount: Int
    public let recitationConfirmed: Bool
    public let completedAt: Date?

    public var id: String { planID }

    public var isComplete: Bool {
        unitCount > 0 && coveredCount == unitCount && recitationConfirmed
    }

    public var carriedOverCount: Int { max(masteredCount - coveredCount, 0) }

    public var isStarted: Bool { masteredCount > 0 || inProgressCount > 0 }

    public var fraction: Double {
        unitCount == 0 ? 0 : Double(masteredCount) / Double(unitCount)
    }
}

/// Progress across the whole Bible.
public struct OverallProgress: Hashable, Sendable {
    public let verseCount: Int
    public let masteredVerses: Int
    public let chapterCount: Int
    public let memorizedChapters: Int
    public let startedChapters: Int
    public let completedPlans: Int

    public var fraction: Double {
        verseCount == 0 ? 0 : Double(masteredVerses) / Double(verseCount)
    }
}

/// Derives everything the UI shows from the verse-level truth in the snapshot.
public struct ProgressReport {
    let content: ContentStore
    let clock: any AppClock

    public init(content: ContentStore, clock: any AppClock) {
        self.content = content
        self.clock = clock
    }

    // MARK: - Chapters

    public func chapterProgress(_ ref: ChapterRef, in progress: ProgressSnapshot) -> ChapterProgress {
        let summary = content.summary(for: ref)
        let chapterState = progress.state(for: ref)
        let states = progress.verseStates(in: ref)
        let include = progress.includeSuperscriptions && (summary?.hasSuperscription ?? false)

        var unitCount = summary?.verseCount ?? 0
        if include { unitCount += 1 }

        var mastered = 0
        var inProgress = 0
        for (verseNumber, state) in states {
            // Verse 0 only counts when headings are being memorized (§7.5).
            if verseNumber == 0 && !include { continue }
            switch state.status {
            case .mastered: mastered += 1
            case .inProgress: inProgress += 1
            case .untouched: break
            }
        }

        let covered = progress.coveredUnits[.chapter(ref)]?.filter {
            include || !$0.isSuperscription
        }
        return ChapterProgress(
            ref: ref,
            unitCount: unitCount,
            masteredCount: min(mastered, unitCount),
            coveredCount: min(covered?.count ?? 0, unitCount),
            inProgressCount: inProgress,
            recitationConfirmed: isRecitationConfirmed(ref, state: chapterState, summary: summary),
            isStartedAsChapter: chapterState.startedAt != nil,
            completedAt: chapterState.completedAt
        )
    }

    private func isRecitationConfirmed(
        _ ref: ChapterRef,
        state: ChapterState,
        summary: ChapterSummary?
    ) -> Bool {
        guard let stanzas = summary?.stanzas, !stanzas.isEmpty else {
            return state.fullRecitationConfirmed
        }
        return stanzas.allSatisfy { state.confirmedStanzas.contains($0.index) }
    }

    // MARK: - Books

    public func bookProgress(_ id: BookID, in progress: ProgressSnapshot) -> BookProgress {
        guard let book = content.book(id) else {
            return BookProgress(
                book: id, chapterCount: 0, memorizedChapters: 0, startedChapters: 0,
                verseCount: 0, masteredVerses: 0
            )
        }
        var memorized = 0
        var started = 0
        for summary in book.chapters {
            let chapter = chapterProgress(ChapterRef(id, summary.number), in: progress)
            if chapter.isMemorized {
                memorized += 1
            } else if chapter.isStartedAsChapter {
                started += 1
            }
        }
        let mastered = progress.verseStates.reduce(into: 0) { total, entry in
            if entry.key.book == id, entry.value.status == .mastered { total += 1 }
        }
        return BookProgress(
            book: id,
            chapterCount: book.chapterCount,
            memorizedChapters: memorized,
            startedChapters: started,
            verseCount: book.verseCount,
            masteredVerses: mastered
        )
    }

    /// Books the user has touched, in canonical order.
    public func startedBooks(in progress: ProgressSnapshot) -> [BookSummary] {
        let touched = Set(progress.verseStates.filter { $0.value.isStarted }.map(\.key.book))
        return content.books.filter { touched.contains($0.id) }.sorted { $0.order < $1.order }
    }

    // MARK: - Plans

    public func planProgress(_ plan: MemoryPlan, in progress: ProgressSnapshot) -> PlanProgress {
        let target = target(for: plan, in: progress)
        var mastered = 0
        var inProgress = 0
        for ref in target.units {
            switch progress.state(for: ref).status {
            case .mastered: mastered += 1
            case .inProgress: inProgress += 1
            case .untouched: break
            }
        }
        let confirmed = progress.confirmedPlanBlocks[plan.id] ?? []
        return PlanProgress(
            planID: plan.id,
            unitCount: target.units.count,
            masteredCount: mastered,
            coveredCount: progress.coveredCount(for: .plan(plan.id), among: target.units),
            inProgressCount: inProgress,
            recitationConfirmed: !target.blocks.isEmpty
                && target.blocks.allSatisfy { confirmed.contains($0.index) },
            completedAt: progress.completedPlans[plan.id]
        )
    }

    /// Built-in plans the user has not hidden, followed by their own. The
    /// walkthrough's demo plan leads the list, but only while the walkthrough
    /// is running.
    public func plans(in progress: ProgressSnapshot) -> [MemoryPlan] {
        let demo = progress.onboarding.isActive ? [BuiltInPlans.walkthrough] : []
        return demo
            + BuiltInPlans.all.filter { !progress.hiddenBuiltInPlans.contains($0.id) }
            + progress.customPlans
    }

    /// Resolves any plan by id, including the demo plan when it is not listed,
    /// so progress recorded against it still reads.
    public func plan(id: String, in progress: ProgressSnapshot) -> MemoryPlan? {
        if id == BuiltInPlans.walkthroughID { return BuiltInPlans.walkthrough }
        return progress.customPlans.first { $0.id == id } ?? BuiltInPlans.plan(id: id)
    }

    // MARK: - Targets

    /// Resolves a chapter into something a session can run.
    public func target(for chapter: Chapter, in progress: ProgressSnapshot) -> MemoryTarget {
        MemoryTarget.chapter(
            chapter,
            title: content.title(for: chapter.ref),
            includingSuperscription: progress.includeSuperscriptions
        )
    }

    /// Resolves a plan into something a session can run, dropping any verse the
    /// translation does not carry.
    public func target(for plan: MemoryPlan, in progress: ProgressSnapshot) -> MemoryTarget {
        MemoryTarget.plan(plan) { chapterRef in
            guard let summary = content.summary(for: chapterRef) else { return [] }
            // The manifest gives counts, not the numbers themselves; load the
            // chapter when a plan touches one with a gap in its numbering.
            if summary.firstVerse == 1,
                let last = summary.firstVerse + summary.verseCount - 1 as Int?,
                (try? content.chapter(chapterRef))?.verseNumbers.count == summary.verseCount
            {
                return Set(summary.firstVerse...last)
            }
            return Set((try? content.chapter(chapterRef))?.verseNumbers ?? [])
        }
    }

    /// Whether a target has been finished, whichever kind it is.
    public func isComplete(_ id: MemoryTargetID, in progress: ProgressSnapshot) -> Bool {
        switch id {
        case let .chapter(ref):
            return chapterProgress(ref, in: progress).isMemorized
        case let .plan(planID):
            guard let plan = plan(id: planID, in: progress) else { return false }
            return planProgress(plan, in: progress).isComplete
        }
    }

    // MARK: - Overall

    public func overall(in progress: ProgressSnapshot) -> OverallProgress {
        let mastered = progress.verseStates.reduce(into: 0) { total, entry in
            if entry.value.status == .mastered { total += 1 }
        }
        var memorized = 0
        var started = 0
        for ref in touchedChapters(in: progress) {
            let chapter = chapterProgress(ref, in: progress)
            if chapter.isMemorized {
                memorized += 1
            } else if chapter.isStartedAsChapter {
                started += 1
            }
        }
        return OverallProgress(
            verseCount: content.verseCount,
            masteredVerses: mastered,
            chapterCount: content.manifest.chapterCount,
            memorizedChapters: memorized,
            startedChapters: started,
            completedPlans: progress.completedPlans.count
        )
    }

    /// Chapters with any recorded work, in any context. Iterating these rather
    /// than all 1,189 keeps the dashboard cheap.
    public func touchedChapters(in progress: ProgressSnapshot) -> [ChapterRef] {
        var refs = Set(progress.verseStates.filter { $0.value.isStarted }.map(\.key.chapterRef))
        refs.formUnion(progress.chapterStates.keys)
        return refs.sorted { lhs, rhs in
            let leftOrder = content.book(lhs.book)?.order ?? 0
            let rightOrder = content.book(rhs.book)?.order ?? 0
            return (leftOrder, lhs.chapter) < (rightOrder, rhs.chapter)
        }
    }

    /// Chapters the user has worked *as chapters* and not yet finished. A plan
    /// quoting a verse does not put its chapter here.
    public func chaptersInProgress(in progress: ProgressSnapshot) -> [ChapterProgress] {
        progress.chapterStates.keys
            .map { chapterProgress($0, in: progress) }
            .filter { $0.isStartedAsChapter && !$0.isMemorized }
            .sorted { lhs, rhs in
                let leftOrder = content.book(lhs.ref.book)?.order ?? 0
                let rightOrder = content.book(rhs.ref.book)?.order ?? 0
                return (leftOrder, lhs.ref.chapter) < (rightOrder, rhs.ref.chapter)
            }
    }

    public func memorizedChapters(in progress: ProgressSnapshot) -> [ChapterProgress] {
        touchedChapters(in: progress)
            .map { chapterProgress($0, in: progress) }
            .filter(\.isMemorized)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// The next chapter to suggest: the one after the last chapter worked on,
    /// falling back to Psalm 1.
    public func nextSuggestedChapter(in progress: ProgressSnapshot) -> ChapterRef {
        if let current = progress.currentTarget.chapterRef,
            !chapterProgress(current, in: progress).isMemorized
        {
            return current
        }
        if let current = progress.currentTarget.chapterRef,
            let book = content.book(current.book),
            current.chapter < book.chapterCount
        {
            return ChapterRef(current.book, current.chapter + 1)
        }
        return ChapterRef(.psalms, 1)
    }
}
