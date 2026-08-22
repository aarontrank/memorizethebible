import XCTest

@testable import BibleCore

/// Coverage is per context; mastery is per verse.
///
/// Learning Romans 3:23 on the Roman Road memorizes the verse, but it does not
/// mean the user has worked Romans 3. These tests pin that distinction down at
/// every level it shows up: the dashboard, the chapter list, and the session.
final class CoverageTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!

    private let romans = BookID("ROM")
    private var chapterRef: ChapterRef { ChapterRef(romans, 3) }
    private var plan: MemoryPlan {
        MemoryPlan(id: "p", title: "Two verses", passages: [PassageRef(romans, 3, 23)])
    }

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([Fixture.chapter(3, verseCount: 31, book: romans)])
        report = ProgressReport(content: content, clock: clock)
    }

    private func engine(_ target: MemoryTarget, _ snapshot: ProgressSnapshot) -> SessionEngine {
        SessionEngine(target: target, snapshot: snapshot, clock: clock)
    }

    private func chapterTarget(_ snapshot: ProgressSnapshot) throws -> MemoryTarget {
        report.target(for: try content.chapter(chapterRef), in: snapshot)
    }

    /// The state after learning Romans 3:23 inside a plan.
    private func afterPlan() throws -> ProgressSnapshot {
        let snapshot = ProgressSnapshot()
        let engine = engine(report.target(for: plan, in: snapshot), snapshot)
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()  // the plan's cumulative pass
        return engine.snapshot
    }

    // MARK: - A plan does not start a chapter

    func testLearningAVerseInAPlanMemorizesIt() throws {
        let snapshot = try afterPlan()
        XCTAssertEqual(snapshot.state(for: VerseRef(romans, 3, 23)).status, .mastered)
    }

    func testAPlanDoesNotMarkTheChapterStarted() throws {
        let progress = report.chapterProgress(chapterRef, in: try afterPlan())
        XCTAssertFalse(
            progress.isStartedAsChapter,
            "learning Romans 3:23 on the Roman Road is not starting Romans 3"
        )
    }

    func testAPlanKeepsTheChapterOutOfTheInProgressList() throws {
        XCTAssertTrue(report.chaptersInProgress(in: try afterPlan()).isEmpty)
    }

    func testTheChapterStillCountsTheVerseItKnows() throws {
        let progress = report.chapterProgress(chapterRef, in: try afterPlan())
        XCTAssertEqual(progress.masteredCount, 1, "the list should read 1 of 31 verses")
        XCTAssertEqual(progress.unitCount, 31)
        XCTAssertEqual(progress.coveredCount, 0, "but nothing has been worked in the chapter")
        XCTAssertEqual(progress.carriedOverCount, 1)
        XCTAssertTrue(progress.isStarted, "so lists still show a tally rather than a first line")
    }

    func testWorkingTheChapterDoesMarkItStarted() throws {
        var snapshot = try afterPlan()
        let engine = engine(try chapterTarget(snapshot), snapshot)
        engine.confirmCurrentStep()  // one read of verse 1
        snapshot = engine.snapshot
        XCTAssertTrue(report.chapterProgress(chapterRef, in: snapshot).isStartedAsChapter)
        XCTAssertEqual(report.chaptersInProgress(in: snapshot).map(\.ref), [chapterRef])
    }

    // MARK: - Meeting a verse you already know

    func testTheSessionStartsAtVerseOneNotAtTheKnownVerse() throws {
        let engine = engine(try chapterTarget(try afterPlan()), try afterPlan())
        XCTAssertEqual(
            engine.step, .read(VerseRef(romans, 3, 1)),
            "verses before the known one are worked as normal"
        )
    }

    /// Walk the chapter up to the verse the plan already taught.
    private func engineAtVerse23() throws -> SessionEngine {
        var snapshot = try afterPlan()
        for verse in 1...22 {
            let ref = VerseRef(romans, 3, verse)
            snapshot.update(ref) { state in
                state.status = .mastered
                state.masteredAt = clock.now
                state.readCount = SessionRules.requiredReads
                state.highestMaskLevelCleared = 4
            }
            snapshot.markCovered(ref, by: .chapter(chapterRef))
        }
        snapshot.update(chapterRef) {
            $0.cumulativeConfirmedThrough = 22
            $0.startedAt = clock.now
        }
        return engine(try chapterTarget(snapshot), snapshot)
    }

    func testAKnownVerseStopsTheSessionToAskRatherThanBeingSkipped() throws {
        XCTAssertEqual(try engineAtVerse23().step, .carriedOver(VerseRef(romans, 3, 23)))
    }

    func testKnownVersesAreMarkedInTheText() throws {
        let engine = try engineAtVerse23()
        XCTAssertEqual(engine.carriedOverUnits, [VerseRef(romans, 3, 23)])
    }

    func testKeepingItMarksItWorkedAndMovesOn() throws {
        let engine = try engineAtVerse23()
        engine.keepCarriedOver(VerseRef(romans, 3, 23))

        XCTAssertTrue(engine.snapshot.isCovered(VerseRef(romans, 3, 23), by: .chapter(chapterRef)))
        XCTAssertEqual(
            engine.step,
            .cumulative(units: Array(1...23).map { VerseRef(romans, 3, $0) }, after: VerseRef(romans, 3, 23)),
            "it is still strung together with its neighbours"
        )
    }

    func testRelearningRunsTheVerseThroughTheWholeLoopAgain() throws {
        let engine = try engineAtVerse23()
        engine.relearnCarriedOver(VerseRef(romans, 3, 23))

        XCTAssertEqual(engine.step, .read(VerseRef(romans, 3, 23)))
        XCTAssertEqual(engine.readsRemaining, SessionRules.requiredReads)
    }

    func testRelearningNeverGivesUpTheMasteryAlreadyEarned() throws {
        let engine = try engineAtVerse23()
        engine.relearnCarriedOver(VerseRef(romans, 3, 23))
        XCTAssertEqual(
            engine.state(VerseRef(romans, 3, 23)).status,
            .mastered,
            "stopping halfway through a redo must not cost the user the verse"
        )
    }

    func testTheChoiceIsOfferedAgainIfTheRedoIsAbandoned() throws {
        let engine = try engineAtVerse23()
        engine.relearnCarriedOver(VerseRef(romans, 3, 23))
        // Quit and come back: the verse is still known but still not worked.
        let resumed = self.engine(try chapterTarget(engine.snapshot), engine.snapshot)
        XCTAssertEqual(resumed.step, .carriedOver(VerseRef(romans, 3, 23)))
    }

    func testVersesAfterAKnownOneAreWorkedAsNormal() throws {
        let engine = try engineAtVerse23()
        engine.keepCarriedOver(VerseRef(romans, 3, 23))
        engine.confirmCurrentStep()  // the cumulative pass
        XCTAssertEqual(engine.step, .read(VerseRef(romans, 3, 24)))
    }

    // MARK: - Completion

    func testAChapterIsNotFinishedUntilEveryVerseHasBeenMetHere() throws {
        var snapshot = ProgressSnapshot()
        // Every verse memorized elsewhere, nothing worked in the chapter.
        for verse in 1...31 {
            snapshot.update(VerseRef(romans, 3, verse)) { state in
                state.status = .mastered
                state.masteredAt = clock.now
            }
        }
        snapshot.update(chapterRef) { $0.fullRecitationConfirmed = true }

        let progress = report.chapterProgress(chapterRef, in: snapshot)
        XCTAssertEqual(progress.masteredCount, 31)
        XCTAssertFalse(progress.isMemorized, "knowing the verses is not the same as having worked it")

        let engine = engine(try chapterTarget(snapshot), snapshot)
        XCTAssertEqual(engine.step, .carriedOver(VerseRef(romans, 3, 1)))
    }

    func testKeepingEveryVerseFinishesTheChapter() throws {
        var snapshot = ProgressSnapshot()
        for verse in 1...31 {
            snapshot.update(VerseRef(romans, 3, verse)) { state in
                state.status = .mastered
                state.masteredAt = clock.now
            }
        }
        var engine = engine(try chapterTarget(snapshot), snapshot)
        var guardCount = 0
        while engine.step != .done, guardCount < 200 {
            engine.confirmCurrentStep()
            guardCount += 1
        }
        XCTAssertLessThan(guardCount, 200, "the session did not terminate")
        XCTAssertTrue(report.chapterProgress(chapterRef, in: engine.snapshot).isMemorized)
        engine = self.engine(try chapterTarget(engine.snapshot), engine.snapshot)
        XCTAssertEqual(engine.step, .done)
    }

    // MARK: - Plans see the same courtesy

    func testAPlanAlsoAsksAboutAVerseLearnedInItsChapter() throws {
        var snapshot = ProgressSnapshot()
        snapshot.update(VerseRef(romans, 3, 23)) { state in
            state.status = .mastered
            state.masteredAt = clock.now
        }
        snapshot.markCovered(VerseRef(romans, 3, 23), by: .chapter(chapterRef))

        let engine = engine(report.target(for: plan, in: snapshot), snapshot)
        XCTAssertEqual(
            engine.step, .carriedOver(VerseRef(romans, 3, 23)),
            "the rule runs both ways: a plan does not assume chapter work either"
        )
    }
}

/// Finishing something: the signal that drives going home and celebrating.
final class CompletionSignalTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!

    private let book = Fixture.testBook
    private var chapterRef: ChapterRef { ChapterRef(book, 1) }

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([Fixture.chapter(1, verseCount: 2, book: book)])
        report = ProgressReport(content: content, clock: clock)
    }

    private func engine(_ snapshot: ProgressSnapshot) throws -> SessionEngine {
        SessionEngine(
            target: report.target(for: try content.chapter(chapterRef), in: snapshot),
            snapshot: snapshot,
            clock: clock
        )
    }

    func testNothingIsClaimedFinishedBeforeItIs() throws {
        let engine = try engine(ProgressSnapshot())
        XCTAssertFalse(engine.justCompletedTarget)
        engine.takeVerseToMastered()
        XCTAssertFalse(engine.justCompletedTarget, "one verse of two is not finishing")
    }

    func testFinishingRaisesTheSignal() throws {
        let engine = try engine(ProgressSnapshot())
        var guardCount = 0
        while engine.step != .done, guardCount < 40 {
            engine.confirmCurrentStep()
            guardCount += 1
        }
        XCTAssertLessThan(guardCount, 40)
        XCTAssertTrue(engine.justCompletedTarget)
    }

    /// Opening something already finished must not celebrate it all over again.
    func testReopeningAFinishedTargetRaisesNothing() throws {
        let first = try engine(ProgressSnapshot())
        var guardCount = 0
        while first.step != .done, guardCount < 40 {
            first.confirmCurrentStep()
            guardCount += 1
        }

        let reopened = try engine(first.snapshot)
        XCTAssertEqual(reopened.step, .done)
        XCTAssertFalse(
            reopened.justCompletedTarget,
            "the celebration belongs to the moment it happened"
        )
    }

    func testCompletionIsReportedForEitherKindOfTarget() throws {
        var snapshot = ProgressSnapshot()
        XCTAssertFalse(report.isComplete(.chapter(chapterRef), in: snapshot))

        let engine = try engine(snapshot)
        var guardCount = 0
        while engine.step != .done, guardCount < 40 {
            engine.confirmCurrentStep()
            guardCount += 1
        }
        snapshot = engine.snapshot
        XCTAssertTrue(report.isComplete(.chapter(chapterRef), in: snapshot))
        XCTAssertFalse(
            report.isComplete(.plan("nope"), in: snapshot),
            "a plan that does not exist is not complete"
        )
    }
}
