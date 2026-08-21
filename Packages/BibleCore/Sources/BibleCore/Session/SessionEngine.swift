import Foundation
import Observation

/// One unit of work in a session (§7.1).
public enum SessionStep: Equatable, Sendable {
    /// Phase 1: read the verse in full, `SessionRules.requiredReads` times.
    case read(VerseRef)
    /// Phases 2–3: the recall ladder up to a clean level-4 pass.
    case ladder(VerseRef)
    /// A verse already memorized somewhere else, met here for the first time.
    /// Knowing it in one context does not make it ready in another, so the
    /// choice is the user's: keep it, or work it again from the top.
    case carriedOver(VerseRef)
    /// Phase 4: recite the accumulated block. Required, not skippable.
    case cumulative(units: [VerseRef], after: VerseRef)
    /// The closing recitation that turns a fully mastered target into a
    /// memorized one — per block for long chapters and multi-section plans.
    case recitation(blockIndex: Int)
    /// Everything is memorized; nothing left to do.
    case done
}

/// Why the primary button says what it says.
public enum PrimaryActionState: Equatable, Sendable {
    case enabled
    /// Level 4 reached, but the attempt was not clean (§7.3).
    case blockedByPeek
    /// Still reading; `remaining` more reads to go (§7.1).
    case moreReadsRequired(remaining: Int)
}

/// Drives a target through read → ladder → mastered → cumulative (§7.1).
///
/// The engine has no idea whether it was handed a chapter or a memory plan: a
/// `MemoryTarget` is just an ordered list of verses plus the blocks they are
/// recited in. Mastery is recorded against the verse reference, so learning
/// Romans 3:23 in the Roman Road is the same work as learning it in Romans 3.
///
/// Pure logic: no UI, no `Date()`, no file I/O. Mutations land in `snapshot`
/// and are handed to `persist` so the caller can write them out.
@Observable
public final class SessionEngine {
    public private(set) var snapshot: ProgressSnapshot
    public private(set) var step: SessionStep
    /// The level currently displayed. Bounded 0...4; "show more" steps down.
    public private(set) var level: MaskLevel
    /// Set by a peek; blocks mastery at level 4 until the attempt restarts.
    public private(set) var attemptHasPeek: Bool = false
    public let target: MemoryTarget

    /// Verses the user chose to work again this session. Deliberately not
    /// persisted: abandoning halfway leaves the verse as it was, still
    /// memorized, and the choice is simply offered again.
    private var relearning: Set<VerseRef> = []

    private let clock: any AppClock
    private let persist: (ProgressSnapshot) -> Void

    public init(
        target: MemoryTarget,
        snapshot: ProgressSnapshot,
        clock: any AppClock,
        persist: @escaping (ProgressSnapshot) -> Void = { _ in }
    ) {
        self.target = target
        self.snapshot = snapshot
        self.clock = clock
        self.persist = persist
        self.step = .done
        self.level = .none

        self.snapshot.currentTarget = target.id
        advanceToNextStep()
        self.snapshot.lastOpenedAt = clock.now
        save()
    }

    // MARK: - Derived state for the UI

    /// Units rendered at full opacity; everything else is dimmed but visible
    /// (§8.2).
    public var activeUnits: [VerseRef] {
        switch step {
        case let .read(ref), let .ladder(ref), let .carriedOver(ref): return [ref]
        case let .cumulative(units, _): return units
        case let .recitation(index):
            return target.blocks.first { $0.index == index }?.units ?? target.units
        case .done: return []
        }
    }

    /// The verse the session is centred on, for resume and for scrolling.
    public var focusVerse: VerseRef? {
        switch step {
        case let .read(ref), let .ladder(ref), let .carriedOver(ref): return ref
        case let .cumulative(_, after): return after
        case let .recitation(index):
            return target.blocks.first { $0.index == index }?.units.first
        case .done: return nil
        }
    }

    /// Chapters whose text the screen needs right now. More than one only for a
    /// plan whose block crosses books.
    public var activeChapters: [ChapterRef] {
        var seen: Set<ChapterRef> = []
        return activeUnits.compactMap {
            seen.insert($0.chapterRef).inserted ? $0.chapterRef : nil
        }
    }

    public var readsRemaining: Int {
        guard case let .read(ref) = step else { return 0 }
        return max(0, SessionRules.requiredReads - state(ref).readCount)
    }

    public var primaryActionState: PrimaryActionState {
        switch step {
        case .read:
            return readsRemaining > 0 ? .moreReadsRequired(remaining: readsRemaining) : .enabled
        case .ladder:
            return level == .full && attemptHasPeek ? .blockedByPeek : .enabled
        case .cumulative, .recitation, .carriedOver, .done:
            return .enabled
        }
    }

    /// True when "I know it" would master the verse (§7.1).
    public var isAtMasteryRung: Bool {
        if case .ladder = step { return level == .full }
        return false
    }

    public var canShowMore: Bool { level > .none }
    public var canShowLess: Bool { level < .full }

    public func state(_ ref: VerseRef) -> VerseState { snapshot.state(for: ref) }

    /// How far through the target the session is, for "verse 4 of 12".
    public var positionInTarget: Int? {
        focusVerse.flatMap { target.position(of: $0) }.map { $0 + 1 }
    }

    public var unitCount: Int { target.units.count }

    /// Units this target has worked through, which is what "12 of 39" counts.
    public var coveredCount: Int {
        snapshot.coveredCount(for: target.id, among: target.units)
    }

    /// Verses in this target already memorized elsewhere and not yet worked
    /// here — marked in the text so the reason they look different is obvious.
    public var carriedOverUnits: Set<VerseRef> {
        Set(
            target.units.filter {
                snapshot.state(for: $0).status == .mastered
                    && !snapshot.isCovered($0, by: target.id)
            }
        )
    }

    /// The block currently being recited, when there is one.
    public var currentBlock: MemoryBlock? {
        guard case let .recitation(index) = step else { return nil }
        return target.blocks.first { $0.index == index }
    }

    // MARK: - Level controls (§7.1)

    /// Reveals words. Never touches the high-water mark.
    public func showMore() {
        guard canShowMore else { return }
        level = level.showingMore
    }

    public func showLess() {
        guard canShowLess else { return }
        level = level.showingLess
    }

    /// §7.3: reveal one word briefly. The count is permanent; the block on
    /// mastery lasts only for the current attempt.
    public func recordPeek(_ ref: VerseRef) {
        attemptHasPeek = true
        mutate { $0.update(ref) { $0.peekCount += 1 } }
    }

    /// §7.1 phase 3: a peek at level 4 resets the attempt, not the high-water
    /// mark.
    public func restartAttempt() {
        attemptHasPeek = false
    }

    // MARK: - Primary actions

    public func confirmCurrentStep() {
        switch step {
        case let .read(ref):
            recordRead(ref)
        case let .ladder(ref):
            clearLadderRung(ref)
        case let .cumulative(_, after):
            recordCumulativePass(after: after)
        case let .recitation(index):
            recordRecitation(blockIndex: index)
        case let .carriedOver(ref):
            keepCarriedOver(ref)
        case .done:
            break
        }
    }

    /// "I still know it": accept the verse as worked here without redoing it.
    /// The cumulative pass still follows, so it gets strung together with its
    /// neighbours in this context.
    public func keepCarriedOver(_ ref: VerseRef) {
        mutate { $0.markCovered(ref, by: self.target.id) }
        advanceToNextStep()
    }

    /// "Memorize it again": run the verse through the normal loop from the top.
    /// Its existing mastery is left alone, so nothing is lost by stopping.
    public func relearnCarriedOver(_ ref: VerseRef) {
        relearning.insert(ref)
        mutate { $0.update(ref) { $0.readCount = 0 } }
        advanceToNextStep()
    }

    /// The negative action: on the ladder it steps back a rung, and on a block
    /// pass it drops to a supported level (§7.1).
    public func reportMiss() {
        switch step {
        case .ladder:
            showMore()
            attemptHasPeek = false
        case .cumulative, .recitation:
            level = SessionRules.supportedCumulativeLevel
        case let .carriedOver(ref):
            // "Not sure" on a carry-over is the same as choosing to redo it.
            relearnCarriedOver(ref)
        case .read, .done:
            break
        }
    }

    private func recordRead(_ ref: VerseRef) {
        mutate { snapshot in
            snapshot.update(ref) { state in
                state.readCount += 1
                if state.status == .untouched { state.status = .inProgress }
            }
            self.markChapterStarted(&snapshot)
        }
        if state(ref).readCount >= SessionRules.requiredReads {
            beginLadder(ref)
        }
    }

    private func clearLadderRung(_ ref: VerseRef) {
        // A clean level-4 pass masters the verse (§7.1 phase 3).
        if level == .full {
            guard !attemptHasPeek else { return }
            mutate { snapshot in
                snapshot.update(ref) { state in
                    state.recordCleared(level: .full)
                    if state.status != .mastered {
                        state.status = .mastered
                        state.masteredAt = self.clock.now
                    }
                }
                snapshot.markCovered(ref, by: self.target.id)
                self.markChapterStarted(&snapshot)
            }
            relearning.remove(ref)
            advanceToNextStep()
            return
        }

        let cleared = level
        mutate { snapshot in
            snapshot.update(ref) { state in
                state.recordCleared(level: cleared)
                if state.status == .untouched { state.status = .inProgress }
            }
        }
        level = level.showingLess
        attemptHasPeek = false
    }

    /// §7.1 phase 4. The cumulative pass confers no mastery of its own; it
    /// records that the accumulated block was recited.
    private func recordCumulativePass(after ref: VerseRef) {
        let position = (target.position(of: ref) ?? 0) + 1
        mutate { snapshot in
            if self.target.chapterRef != nil {
                snapshot.update(ref.chapterRef) { state in
                    state.cumulativeConfirmedThrough = max(
                        state.cumulativeConfirmedThrough, ref.verse
                    )
                }
            } else if let planID = self.target.planID {
                snapshot.planCumulativeProgress[planID] = max(
                    snapshot.planCumulativeProgress[planID] ?? 0, position
                )
            }
        }
        advanceToNextStep()
    }

    private func recordRecitation(blockIndex: Int) {
        mutate { snapshot in
            if let chapterRef = self.target.chapterRef {
                snapshot.update(chapterRef) { state in
                    if self.target.blocks.count > 1 {
                        state.confirmedStanzas.insert(blockIndex)
                    } else {
                        state.fullRecitationConfirmed = true
                    }
                }
            } else if let planID = self.target.planID {
                snapshot.confirmedPlanBlocks[planID, default: []].insert(blockIndex)
            }
        }
        markCompletionIfFinished()
        advanceToNextStep()
    }

    /// Records that this chapter has been worked as a chapter, which is what
    /// puts it in the dashboard's in-progress list. A plan quoting one of its
    /// verses never sets this.
    private func markChapterStarted(_ snapshot: inout ProgressSnapshot) {
        guard let chapterRef = target.chapterRef else { return }
        if snapshot.state(for: chapterRef).startedAt == nil {
            snapshot.update(chapterRef) { $0.startedAt = self.clock.now }
        }
    }

    private func beginLadder(_ ref: VerseRef) {
        step = .ladder(ref)
        attemptHasPeek = false
        // Resume above the high-water mark, so returning to a half-learned
        // verse does not restart at 25%.
        let cleared = state(ref).highestLevel
        level = cleared == .full ? .full : cleared.showingLess
    }

    /// Recomputes the next step from persisted state alone, so quitting and
    /// relaunching resumes on the exact verse and phase.
    private func advanceToNextStep() {
        attemptHasPeek = false

        guard !target.isEmpty else {
            step = .done
            level = .none
            return
        }

        // 1. An owed cumulative pass blocks new material (§7.1: required, not
        //    skippable) — including across an app relaunch.
        if let owed = owedCumulativeUnit() {
            step = .cumulative(units: target.cumulativeUnits(upTo: owed).map(\.ref), after: owed)
            level = .full
            return
        }

        // 2. The next verse this target has not worked through. Coverage, not
        //    mastery: a verse learned elsewhere still gets its moment here.
        if let next = target.units.first(where: { !snapshot.isCovered($0, by: target.id) }) {
            snapshot.currentVerse = next
            if snapshot.state(for: next).status == .mastered, !relearning.contains(next) {
                step = .carriedOver(next)
                level = .none
                return
            }
            if snapshot.state(for: next).readCount < SessionRules.requiredReads {
                step = .read(next)
                level = .none
            } else {
                beginLadder(next)
            }
            return
        }

        // 3. Every verse is worked: all that remains is the closing
        //    recitation (§7.1).
        if let block = target.blocks.first(where: { !isRecitationConfirmed(blockIndex: $0.index) }) {
            step = .recitation(blockIndex: block.index)
            level = .full
            return
        }

        step = .done
        level = .none
    }

    /// The most recent mastered verse whose cumulative pass has not been
    /// recorded.
    private func owedCumulativeUnit() -> VerseRef? {
        let worked = target.units.filter { snapshot.isCovered($0, by: target.id) }
        guard let latest = worked.last else { return nil }
        // A psalm heading on its own is not worth a cumulative pass.
        guard latest.verse > 0 else { return nil }

        if target.chapterRef != nil {
            let confirmed = snapshot.state(for: latest.chapterRef).cumulativeConfirmedThrough
            return latest.verse > confirmed ? latest : nil
        }
        guard let planID = target.planID else { return nil }
        let confirmed = snapshot.planCumulativeProgress[planID] ?? 0
        let position = (target.position(of: latest) ?? 0) + 1
        return position > confirmed ? latest : nil
    }

    private func isRecitationConfirmed(blockIndex: Int) -> Bool {
        if let chapterRef = target.chapterRef {
            let state = snapshot.state(for: chapterRef)
            return target.blocks.count > 1
                ? state.confirmedStanzas.contains(blockIndex)
                : state.fullRecitationConfirmed
        }
        guard let planID = target.planID else { return true }
        return snapshot.confirmedPlanBlocks[planID]?.contains(blockIndex) ?? false
    }

    private func markCompletionIfFinished() {
        let everythingWorked = target.units.allSatisfy { snapshot.isCovered($0, by: target.id) }
        let recited = target.blocks.allSatisfy { isRecitationConfirmed(blockIndex: $0.index) }
        guard everythingWorked, recited else { return }

        mutate { snapshot in
            if let chapterRef = self.target.chapterRef {
                snapshot.update(chapterRef) { state in
                    if state.completedAt == nil { state.completedAt = self.clock.now }
                }
            } else if let planID = self.target.planID, snapshot.completedPlans[planID] == nil {
                snapshot.completedPlans[planID] = self.clock.now
            }
        }
    }

    // MARK: - Persistence

    private func mutate(_ body: (inout ProgressSnapshot) -> Void) {
        body(&snapshot)
        save()
    }

    private func save() {
        persist(snapshot)
    }
}
