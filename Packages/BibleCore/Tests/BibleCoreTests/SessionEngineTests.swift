import XCTest

@testable import BibleCore

/// The memorization loop, driven by a chapter target.
final class SessionEngineTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!
    private var saved: [ProgressSnapshot] = []

    private let book = Fixture.testBook

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([
            Fixture.chapter(1, verseCount: 2),
            Fixture.chapter(2, verseCount: 6, hasSuperscription: true),
            Fixture.chapter(3, verseCount: 24, stanzaSize: 8),
        ])
        report = ProgressReport(content: content, clock: clock)
        saved = []
    }

    private func engine(
        chapter number: Int = 1,
        snapshot: ProgressSnapshot = ProgressSnapshot()
    ) throws -> SessionEngine {
        let chapter = try content.chapter(ChapterRef(book, number))
        return SessionEngine(
            target: report.target(for: chapter, in: snapshot),
            snapshot: snapshot,
            clock: clock,
            persist: { self.saved.append($0) }
        )
    }

    private func ref(_ chapter: Int, _ verse: Int) -> VerseRef { VerseRef(book, chapter, verse) }

    // MARK: - Reading

    func testSessionOpensOnReadAtFullText() throws {
        let engine = try engine()
        XCTAssertEqual(engine.step, .read(ref(1, 1)))
        XCTAssertEqual(engine.level, .none)
        XCTAssertEqual(engine.primaryActionState, .moreReadsRequired(remaining: 3))
    }

    func testLadderUnlocksOnlyAfterThreeReads() throws {
        let engine = try engine()
        engine.confirmCurrentStep()
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .read(ref(1, 1)))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .ladder(ref(1, 1)), "§7.1: 3 reads unlock the ladder")
        XCTAssertEqual(engine.level, .quarter)
    }

    // MARK: - Ladder and mastery

    func testCleanLevelFourPassMastersTheVerse() throws {
        let engine = try engine()
        engine.takeVerseToMastered()
        let state = engine.state(ref(1, 1))
        XCTAssertEqual(state.status, .mastered)
        XCTAssertEqual(state.masteredAt, clock.now)
        XCTAssertEqual(state.highestMaskLevelCleared, 4)
    }

    func testShowMoreNeverLowersTheHighWaterMark() throws {
        let engine = try engine()
        for _ in 0..<3 { engine.confirmCurrentStep() }
        engine.confirmCurrentStep()
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.state(ref(1, 1)).highestMaskLevelCleared, 2)
        engine.showMore()
        engine.showMore()
        XCTAssertEqual(engine.state(ref(1, 1)).highestMaskLevelCleared, 2)
    }

    func testPeekAtLevelFourBlocksMastery() throws {
        let engine = try engine()
        for _ in 0..<3 { engine.confirmCurrentStep() }
        for _ in 0..<3 { engine.confirmCurrentStep() }
        XCTAssertEqual(engine.level, .full)

        engine.recordPeek(ref(1, 1))
        XCTAssertEqual(engine.primaryActionState, .blockedByPeek)
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.state(ref(1, 1)).status, .inProgress, "§7.3: the attempt must be clean")

        engine.restartAttempt()
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.state(ref(1, 1)).status, .mastered)
    }

    func testResumingStartsAboveTheHighWaterMark() throws {
        var snapshot = ProgressSnapshot()
        snapshot.update(ref(1, 1)) { state in
            state.status = .inProgress
            state.readCount = 3
            state.highestMaskLevelCleared = 2
        }
        let engine = try engine(snapshot: snapshot)
        XCTAssertEqual(engine.step, .ladder(ref(1, 1)))
        XCTAssertEqual(engine.level, .threeQuarters)
    }

    // MARK: - Cumulative passes

    func testCumulativePassIsRequiredAfterEachVerse() throws {
        let engine = try engine()
        engine.takeVerseToMastered()
        XCTAssertEqual(engine.step, .cumulative(units: [ref(1, 1)], after: ref(1, 1)))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .read(ref(1, 2)))
    }

    func testCumulativeBlockAccumulates() throws {
        let engine = try engine(chapter: 2)
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()
        engine.takeVerseToMastered()
        XCTAssertEqual(
            engine.step, .cumulative(units: [ref(2, 1), ref(2, 2)], after: ref(2, 2))
        )
    }

    func testOwedCumulativePassSurvivesQuitting() throws {
        let engine = try engine()
        engine.takeVerseToMastered()
        guard case .cumulative = engine.step else { return XCTFail("expected cumulative") }

        let resumed = try self.engine(snapshot: engine.snapshot)
        XCTAssertEqual(resumed.step, .cumulative(units: [ref(1, 1)], after: ref(1, 1)))
    }

    func testLongChaptersScopeCumulativeReviewToTheStanza() throws {
        var snapshot = ProgressSnapshot()
        for verse in 1...11 {
            snapshot.seedWorked(ref(3, verse), by: .chapter(ChapterRef(book, 3)), at: clock.now)
        }
        snapshot.update(ChapterRef(book, 3)) { $0.cumulativeConfirmedThrough = 10 }

        let engine = try engine(chapter: 3, snapshot: snapshot)
        XCTAssertEqual(
            engine.step,
            .cumulative(units: [ref(3, 9), ref(3, 10), ref(3, 11)], after: ref(3, 11)),
            "§7.6: stanza-scoped, not verses 1...11"
        )
    }

    // MARK: - Completion

    func testChapterNeedsItsClosingRecitation() throws {
        let engine = try engine()
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()

        XCTAssertEqual(engine.step, .recitation(blockIndex: 0))
        XCTAssertFalse(report.chapterProgress(ChapterRef(book, 1), in: engine.snapshot).isMemorized)

        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .done)
        XCTAssertTrue(report.chapterProgress(ChapterRef(book, 1), in: engine.snapshot).isMemorized)
        XCTAssertEqual(engine.snapshot.state(for: ChapterRef(book, 1)).completedAt, clock.now)
    }

    func testLongChapterIsRecitedStanzaByStanza() throws {
        var snapshot = ProgressSnapshot()
        for verse in 1...24 {
            snapshot.seedWorked(ref(3, verse), by: .chapter(ChapterRef(book, 3)), at: clock.now)
        }
        snapshot.update(ChapterRef(book, 3)) { $0.cumulativeConfirmedThrough = 24 }

        let engine = try engine(chapter: 3, snapshot: snapshot)
        XCTAssertEqual(engine.step, .recitation(blockIndex: 0))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .recitation(blockIndex: 1))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .recitation(blockIndex: 2))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .done)
    }

    // MARK: - Headings (§7.5)

    func testHeadingsAreNotMemorizedByDefault() throws {
        let engine = try engine(chapter: 2)
        XCTAssertEqual(engine.target.units.first, ref(2, 1))
        XCTAssertEqual(engine.unitCount, 6)
    }

    func testHeadingsBecomeTheFirstUnitWhenEnabled() throws {
        var snapshot = ProgressSnapshot()
        snapshot.includeSuperscriptions = true
        let engine = try engine(chapter: 2, snapshot: snapshot)
        XCTAssertEqual(engine.target.units.first, ref(2, 0))
        XCTAssertEqual(engine.unitCount, 7)
        XCTAssertEqual(engine.step, .read(ref(2, 0)))
    }

    // MARK: - Persistence

    func testEveryMutationIsPersisted() throws {
        let engine = try engine()
        let before = saved.count
        engine.confirmCurrentStep()
        XCTAssertGreaterThan(saved.count, before)
        XCTAssertEqual(saved.last?.state(for: ref(1, 1)).readCount, 1)
    }

    func testSessionRecordsWhereItIs() throws {
        let engine = try engine()
        XCTAssertEqual(engine.snapshot.currentTarget, .chapter(ChapterRef(book, 1)))
        XCTAssertEqual(engine.snapshot.currentVerse, ref(1, 1))
        XCTAssertEqual(engine.snapshot.lastOpenedAt, clock.now)
    }

    func testResumeLandsOnTheExactVerseAndPhase() throws {
        let engine = try engine(chapter: 2)
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()
        engine.confirmCurrentStep()

        let resumed = try self.engine(chapter: 2, snapshot: engine.snapshot)
        XCTAssertEqual(resumed.step, .read(ref(2, 2)))
        XCTAssertEqual(resumed.readsRemaining, 2)
    }
}
