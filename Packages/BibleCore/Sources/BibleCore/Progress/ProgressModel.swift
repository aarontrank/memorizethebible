import Foundation

// Read-write local progress. Design doc §6. Never leaves the device (§13).

public struct VerseState: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case untouched
        case inProgress
        /// Cleared level 4 with no peeks. Mastery is immediate: the delayed
        /// "provisional" state the design doc described in §7.1 and §7.4 was
        /// removed after use — it read as both confusing and patronising.
        case mastered
    }

    public var status: Status
    /// High-water mark, 0...4. Never decreases: never punish the user by
    /// erasing prior work.
    public var highestMaskLevelCleared: Int
    public var readCount: Int
    public var peekCount: Int
    public var masteredAt: Date?

    public init(
        status: Status = .untouched,
        highestMaskLevelCleared: Int = 0,
        readCount: Int = 0,
        peekCount: Int = 0,
        masteredAt: Date? = nil
    ) {
        self.status = status
        self.highestMaskLevelCleared = highestMaskLevelCleared
        self.readCount = readCount
        self.peekCount = peekCount
        self.masteredAt = masteredAt
    }

    /// Schema 1 wrote a `provisional` status and a `provisionalAt` date. A
    /// verse in that state had already passed level 4 cleanly, so it is read
    /// back as mastered — the work was done, only the bookkeeping changed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? "untouched"
        status = Status(rawValue: rawStatus) ?? (rawStatus == "provisional" ? .mastered : .untouched)
        highestMaskLevelCleared =
            try container.decodeIfPresent(Int.self, forKey: .highestMaskLevelCleared) ?? 0
        readCount = try container.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        peekCount = try container.decodeIfPresent(Int.self, forKey: .peekCount) ?? 0
        let masteredAt = try container.decodeIfPresent(Date.self, forKey: .masteredAt)
        let provisionalAt = try container.decodeIfPresent(Date.self, forKey: .legacyProvisionalAt)
        self.masteredAt = masteredAt ?? (status == .mastered ? provisionalAt : nil)
    }

    private enum CodingKeys: String, CodingKey {
        case status, highestMaskLevelCleared, readCount, peekCount, masteredAt
        case legacyProvisionalAt = "provisionalAt"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(highestMaskLevelCleared, forKey: .highestMaskLevelCleared)
        try container.encode(readCount, forKey: .readCount)
        try container.encode(peekCount, forKey: .peekCount)
        try container.encodeIfPresent(masteredAt, forKey: .masteredAt)
    }

    public var isMastered: Bool { status == .mastered }
    public var isStarted: Bool { status != .untouched }
    public var highestLevel: MaskLevel { MaskLevel(rawValue: highestMaskLevelCleared) ?? .none }

    /// Raise the high-water mark without ever lowering it.
    public mutating func recordCleared(level: MaskLevel) {
        highestMaskLevelCleared = max(highestMaskLevelCleared, level.rawValue)
    }
}

/// Per-chapter bookkeeping that is not about any single verse.
public struct ChapterState: Codable, Hashable, Sendable {
    /// Gates "memorized" for a chapter without stanzas (§7.1).
    public var fullRecitationConfirmed: Bool
    /// For stanza-scoped chapters the recitation is confirmed stanza by
    /// stanza; the chapter completes when every stanza is in this set (§7.6).
    public var confirmedStanzas: Set<Int>
    /// Highest verse whose cumulative pass has been completed (§7.1 phase 4).
    /// Persisted so quitting between "verse mastered" and "block recited" does
    /// not let the required cumulative pass be skipped.
    public var cumulativeConfirmedThrough: Int
    /// When the chapter was first worked *as a chapter*. A plan that happens to
    /// quote one of its verses does not set this: learning Romans 3:23 on the
    /// Roman Road is not starting Romans 3.
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        fullRecitationConfirmed: Bool = false,
        confirmedStanzas: Set<Int> = [],
        cumulativeConfirmedThrough: Int = 0,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.fullRecitationConfirmed = fullRecitationConfirmed
        self.confirmedStanzas = confirmedStanzas
        self.cumulativeConfirmedThrough = cumulativeConfirmedThrough
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullRecitationConfirmed =
            try container.decodeIfPresent(Bool.self, forKey: .fullRecitationConfirmed) ?? false
        confirmedStanzas = try container.decodeIfPresent(Set<Int>.self, forKey: .confirmedStanzas) ?? []
        cumulativeConfirmedThrough =
            try container.decodeIfPresent(Int.self, forKey: .cumulativeConfirmedThrough) ?? 0
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// The user's daily reminder time (§8.4). Stored as components rather than a
/// Date so it survives timezone changes intact.
public struct ReminderTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int = 7, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public static let `default` = ReminderTime()
}

/// What the user is working through: a chapter, or a memory plan.
public enum MemoryTargetID: Hashable, Sendable, Codable {
    case chapter(ChapterRef)
    case plan(String)

    public var chapterRef: ChapterRef? {
        if case let .chapter(ref) = self { return ref }
        return nil
    }

    public var planID: String? {
        if case let .plan(id) = self { return id }
        return nil
    }

    /// "chapter:PSA 23" / "plan:builtin.roman-road", for use as a JSON key.
    public var storageKey: String {
        switch self {
        case let .chapter(ref): return "chapter:\(ref.storageKey)"
        case let .plan(id): return "plan:\(id)"
        }
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("chapter:") {
            guard let ref = ChapterRef(storageKey: String(storageKey.dropFirst(8))) else { return nil }
            self = .chapter(ref)
        } else if storageKey.hasPrefix("plan:") {
            self = .plan(String(storageKey.dropFirst(5)))
        } else {
            return nil
        }
    }
}

public struct ProgressSnapshot: Codable, Hashable, Sendable {
    /// Bump only for a breaking change; `ProgressStore` migrates on load.
    ///
    /// 1 → 2: the provisional verse state was removed.
    /// 2 → 3: progress was re-keyed from psalm numbers to verse references
    ///        when the app grew from Psalms to the whole Bible.
    /// 3 → 4: coverage was split from mastery, so a verse learned in one
    ///        context is no longer assumed worked in another.
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    /// Progress is keyed to the translation, so adding a translation later can
    /// never strand existing work (§4).
    public var translationId: String
    /// Where "Continue" resumes.
    public var currentTarget: MemoryTargetID
    public var currentVerse: VerseRef?
    /// Every verse the user has touched, anywhere in the Bible. This is the
    /// single source of truth: chapters and plans are views over it, so a verse
    /// learned in a plan is already learned in its chapter.
    public var verseStates: [VerseRef: VerseState]
    public var chapterStates: [ChapterRef: ChapterState]
    /// Plans the user made. Built-in plans live in code, not here.
    public var customPlans: [MemoryPlan]
    /// Built-in plans the user has hidden, so the list stays theirs.
    public var hiddenBuiltInPlans: Set<String>
    public var completedPlans: [String: Date]
    /// How far the cumulative pass has been carried through each plan, as a
    /// count of units. Chapters track the same thing by verse number, but a
    /// plan's verses are not consecutive, so position is what counts.
    public var planCumulativeProgress: [String: Int]
    /// Plan sections whose closing recitation is done.
    public var confirmedPlanBlocks: [String: Set<Int>]
    /// Which units each target has worked through in its own right.
    ///
    /// Mastery belongs to the verse; *coverage* belongs to the context. Knowing
    /// Romans 3:23 from the Roman Road does not mean you have worked it inside
    /// Romans 3 — reciting a verse in a chapter is a different act from
    /// reciting it in a plan — so each target tracks what it has covered and
    /// offers the choice when it meets a verse you already know.
    public var coveredUnits: [MemoryTargetID: Set<VerseRef>]
    public var lastOpenedAt: Date
    public var notificationsEnabled: Bool
    public var reminderTime: ReminderTime
    /// §7.5, default off: superscriptions are displayed but not memorized.
    public var includeSuperscriptions: Bool

    public init(
        schemaVersion: Int = ProgressSnapshot.currentSchemaVersion,
        translationId: String = "bsb",
        currentTarget: MemoryTargetID = .chapter(ChapterRef(.psalms, 1)),
        currentVerse: VerseRef? = nil,
        verseStates: [VerseRef: VerseState] = [:],
        chapterStates: [ChapterRef: ChapterState] = [:],
        customPlans: [MemoryPlan] = [],
        hiddenBuiltInPlans: Set<String> = [],
        completedPlans: [String: Date] = [:],
        planCumulativeProgress: [String: Int] = [:],
        confirmedPlanBlocks: [String: Set<Int>] = [:],
        coveredUnits: [MemoryTargetID: Set<VerseRef>] = [:],
        lastOpenedAt: Date = .distantPast,
        notificationsEnabled: Bool = false,
        reminderTime: ReminderTime = .default,
        includeSuperscriptions: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.translationId = translationId
        self.currentTarget = currentTarget
        self.currentVerse = currentVerse
        self.verseStates = verseStates
        self.chapterStates = chapterStates
        self.customPlans = customPlans
        self.hiddenBuiltInPlans = hiddenBuiltInPlans
        self.completedPlans = completedPlans
        self.planCumulativeProgress = planCumulativeProgress
        self.confirmedPlanBlocks = confirmedPlanBlocks
        self.coveredUnits = coveredUnits
        self.lastOpenedAt = lastOpenedAt
        self.notificationsEnabled = notificationsEnabled
        self.reminderTime = reminderTime
        self.includeSuperscriptions = includeSuperscriptions
    }

    // MARK: - Access

    public func state(for ref: VerseRef) -> VerseState { verseStates[ref] ?? VerseState() }

    public mutating func update(_ ref: VerseRef, _ body: (inout VerseState) -> Void) {
        var state = verseStates[ref] ?? VerseState()
        body(&state)
        verseStates[ref] = state
    }

    public func state(for ref: ChapterRef) -> ChapterState { chapterStates[ref] ?? ChapterState() }

    public mutating func update(_ ref: ChapterRef, _ body: (inout ChapterState) -> Void) {
        var state = chapterStates[ref] ?? ChapterState()
        body(&state)
        chapterStates[ref] = state
    }

    /// Verse states belonging to one chapter, keyed by verse number.
    public func verseStates(in ref: ChapterRef) -> [Int: VerseState] {
        var result: [Int: VerseState] = [:]
        for (verseRef, state) in verseStates where verseRef.chapterRef == ref {
            result[verseRef.verse] = state
        }
        return result
    }

    /// Has this target worked through this unit in its own right?
    public func isCovered(_ ref: VerseRef, by target: MemoryTargetID) -> Bool {
        coveredUnits[target]?.contains(ref) ?? false
    }

    public mutating func markCovered(_ ref: VerseRef, by target: MemoryTargetID) {
        coveredUnits[target, default: []].insert(ref)
    }

    public func coveredCount(for target: MemoryTargetID, among units: [VerseRef]) -> Int {
        guard let covered = coveredUnits[target] else { return 0 }
        return units.reduce(into: 0) { total, ref in if covered.contains(ref) { total += 1 } }
    }

    public func hasProgress(in ref: ChapterRef) -> Bool {
        let chapter = state(for: ref)
        if chapter.fullRecitationConfirmed || !chapter.confirmedStanzas.isEmpty { return true }
        return verseStates.contains { $0.key.chapterRef == ref && $0.value.isStarted }
    }

    // MARK: - Codable
    //
    // Reference-keyed dictionaries are written as JSON objects with "PSA 23:1"
    // keys, which keeps a hand-inspected progress file readable.

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, translationId, currentTarget, currentVerse
        case verseStates, chapterStates, customPlans, hiddenBuiltInPlans, completedPlans
        case planCumulativeProgress, confirmedPlanBlocks, coveredUnits
        case lastOpenedAt, notificationsEnabled, reminderTime, includeSuperscriptions
        // Schema 2 and earlier.
        // `currentVerse` is shared: schema 2 wrote an Int there, schema 3
        // writes a VerseRef, and the decoder branches on schemaVersion.
        case legacyPsalmStates = "psalmStates"
        case legacyCurrentPsalm = "currentPsalm"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        translationId = try container.decodeIfPresent(String.self, forKey: .translationId) ?? "bsb"
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? .distantPast
        notificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        reminderTime = try container.decodeIfPresent(ReminderTime.self, forKey: .reminderTime) ?? .default
        includeSuperscriptions =
            try container.decodeIfPresent(Bool.self, forKey: .includeSuperscriptions) ?? false
        customPlans = try container.decodeIfPresent([MemoryPlan].self, forKey: .customPlans) ?? []
        hiddenBuiltInPlans =
            try container.decodeIfPresent(Set<String>.self, forKey: .hiddenBuiltInPlans) ?? []
        completedPlans = try container.decodeIfPresent([String: Date].self, forKey: .completedPlans) ?? [:]
        planCumulativeProgress =
            try container.decodeIfPresent([String: Int].self, forKey: .planCumulativeProgress) ?? [:]
        confirmedPlanBlocks =
            try container.decodeIfPresent([String: Set<Int>].self, forKey: .confirmedPlanBlocks) ?? [:]
        let rawCovered =
            try container.decodeIfPresent([String: [String]].self, forKey: .coveredUnits) ?? [:]
        coveredUnits = Dictionary(
            uniqueKeysWithValues: rawCovered.compactMap { key, value in
                MemoryTargetID(storageKey: key).map { ($0, Set(value.compactMap(VerseRef.init(storageKey:)))) }
            }
        )

        if schemaVersion >= 3 {
            let verses = try container.decodeIfPresent([String: VerseState].self, forKey: .verseStates) ?? [:]
            verseStates = Dictionary(
                uniqueKeysWithValues: verses.compactMap { key, value in
                    VerseRef(storageKey: key).map { ($0, value) }
                }
            )
            let chaptersByKey =
                try container.decodeIfPresent([String: ChapterState].self, forKey: .chapterStates) ?? [:]
            chapterStates = Dictionary(
                uniqueKeysWithValues: chaptersByKey.compactMap { key, value in
                    ChapterRef(storageKey: key).map { ($0, value) }
                }
            )
            currentTarget =
                try container.decodeIfPresent(MemoryTargetID.self, forKey: .currentTarget)
                ?? .chapter(ChapterRef(.psalms, 1))
            currentVerse = try container.decodeIfPresent(VerseRef.self, forKey: .currentVerse)
        } else {
            // Schema 1 and 2 knew only Psalms, keyed by psalm number. Every
            // verse of work moves across to its reference in Psalms.
            let legacy =
                try container.decodeIfPresent([Int: LegacyPsalmState].self, forKey: .legacyPsalmStates) ?? [:]
            var verses: [VerseRef: VerseState] = [:]
            var chapters: [ChapterRef: ChapterState] = [:]
            for (number, state) in legacy {
                for (verseNumber, verseState) in state.verseStates {
                    verses[VerseRef(.psalms, number, verseNumber)] = verseState
                }
                chapters[ChapterRef(.psalms, number)] = ChapterState(
                    fullRecitationConfirmed: state.fullRecitationConfirmed,
                    confirmedStanzas: state.confirmedStanzas,
                    cumulativeConfirmedThrough: state.cumulativeConfirmedThrough,
                    completedAt: state.completedAt
                )
            }
            verseStates = verses
            chapterStates = chapters

            let psalm = try container.decodeIfPresent(Int.self, forKey: .legacyCurrentPsalm) ?? 1
            let verse = try container.decodeIfPresent(Int.self, forKey: .currentVerse) ?? 1
            currentTarget = .chapter(ChapterRef(.psalms, psalm))
            currentVerse = VerseRef(.psalms, psalm, verse)
        }

        if schemaVersion < 4 {
            backfillCoverage()
        }
    }

    /// Before schema 4 there was no coverage, because mastery and coverage were
    /// the same thing. Everything already mastered is treated as covered by its
    /// own chapter, so a finished chapter stays finished rather than reopening
    /// with a carry-over prompt on every verse.
    private mutating func backfillCoverage() {
        for (ref, state) in verseStates where state.status == .mastered {
            coveredUnits[.chapter(ref.chapterRef), default: []].insert(ref)
        }
        for (ref, state) in chapterStates {
            guard state.startedAt == nil else { continue }
            let touched = verseStates.contains { $0.key.chapterRef == ref && $0.value.isStarted }
            if touched || state.cumulativeConfirmedThrough > 0 || state.fullRecitationConfirmed
                || !state.confirmedStanzas.isEmpty
            {
                chapterStates[ref]?.startedAt = state.completedAt ?? .distantPast
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(translationId, forKey: .translationId)
        try container.encode(currentTarget, forKey: .currentTarget)
        try container.encodeIfPresent(currentVerse, forKey: .currentVerse)
        try container.encode(
            Dictionary(uniqueKeysWithValues: verseStates.map { ($0.key.storageKey, $0.value) }),
            forKey: .verseStates
        )
        try container.encode(
            Dictionary(uniqueKeysWithValues: chapterStates.map { ($0.key.storageKey, $0.value) }),
            forKey: .chapterStates
        )
        try container.encode(customPlans, forKey: .customPlans)
        try container.encode(hiddenBuiltInPlans, forKey: .hiddenBuiltInPlans)
        try container.encode(completedPlans, forKey: .completedPlans)
        try container.encode(planCumulativeProgress, forKey: .planCumulativeProgress)
        try container.encode(confirmedPlanBlocks, forKey: .confirmedPlanBlocks)
        try container.encode(
            Dictionary(
                uniqueKeysWithValues: coveredUnits.map {
                    ($0.key.storageKey, $0.value.map(\.storageKey).sorted())
                }
            ),
            forKey: .coveredUnits
        )
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(reminderTime, forKey: .reminderTime)
        try container.encode(includeSuperscriptions, forKey: .includeSuperscriptions)
    }
}

/// Schema 1 and 2 shape, read only, so existing progress survives the move to
/// whole-Bible references.
private struct LegacyPsalmState: Decodable {
    var verseStates: [Int: VerseState] = [:]
    var fullRecitationConfirmed = false
    var confirmedStanzas: Set<Int> = []
    var cumulativeConfirmedThrough = 0
    var completedAt: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verseStates = try container.decodeIfPresent([Int: VerseState].self, forKey: .verseStates) ?? [:]
        fullRecitationConfirmed =
            try container.decodeIfPresent(Bool.self, forKey: .fullRecitationConfirmed) ?? false
        confirmedStanzas = try container.decodeIfPresent(Set<Int>.self, forKey: .confirmedStanzas) ?? []
        cumulativeConfirmedThrough =
            try container.decodeIfPresent(Int.self, forKey: .cumulativeConfirmedThrough) ?? 0
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case verseStates, fullRecitationConfirmed, confirmedStanzas
        case cumulativeConfirmedThrough, completedAt
    }
}
