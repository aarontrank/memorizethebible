import Foundation

/// The "Include psalm headings" setting (§7.5).
///
/// The hard requirement is that the toggle is non-destructive in both
/// directions: enabling adds the heading as a unit and reopens any psalm that
/// was complete without it; disabling excludes it from every count but never
/// deletes its state, so switching back on restores the work.
extension ProgressReport {
    /// Memorized psalms that would reopen if headings were switched on, for the
    /// confirmation sheet §7.5 requires.
    public func chaptersReopenedByIncludingHeadings(in progress: ProgressSnapshot) -> [ChapterRef] {
        guard !progress.includeSuperscriptions else { return [] }
        guard let psalms = content.book(.psalms) else { return [] }
        return psalms.chapters
            .filter(\.hasSuperscription)
            .map { ChapterRef(.psalms, $0.number) }
            .filter { ref in
                chapterProgress(ref, in: progress).isMemorized
                    && progress.state(for: VerseRef(.psalms, ref.chapter, 0)).status != .mastered
            }
    }

    /// Applies the setting. Returns a new snapshot; the original is untouched.
    public func applyingHeadings(_ include: Bool, to progress: ProgressSnapshot) -> ProgressSnapshot {
        var updated = progress
        updated.includeSuperscriptions = include
        guard let psalms = content.book(.psalms) else { return updated }

        for summary in psalms.chapters where summary.hasSuperscription {
            let ref = ChapterRef(.psalms, summary.number)
            let headingRef = VerseRef(.psalms, summary.number, 0)

            if include {
                // Give the heading a state to work against, but only for a
                // psalm the user has actually started.
                if updated.verseStates[headingRef] == nil, updated.hasProgress(in: ref) {
                    updated.verseStates[headingRef] = VerseState()
                }
                if updated.state(for: ref).completedAt != nil,
                    updated.state(for: headingRef).status != .mastered
                {
                    updated.update(ref) { $0.completedAt = nil }
                }
            } else if updated.state(for: ref).completedAt == nil {
                // Turning headings back off can re-complete a psalm whose
                // verses were all mastered before.
                let verses = (1...max(summary.verseCount, 1)).map {
                    VerseRef(.psalms, summary.number, $0)
                }
                let allMastered = verses.allSatisfy { updated.state(for: $0).status == .mastered }
                let chapterState = updated.state(for: ref)
                let recited = chapterState.fullRecitationConfirmed || !chapterState.confirmedStanzas.isEmpty
                if allMastered, recited {
                    let last = verses.compactMap { updated.state(for: $0).masteredAt }.max()
                    updated.update(ref) { $0.completedAt = last }
                }
            }
            // Note what is absent: verse-0 state is never deleted, either way.
        }
        return updated
    }
}
