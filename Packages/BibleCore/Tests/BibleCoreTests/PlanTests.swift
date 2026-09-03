import XCTest

@testable import BibleCore

/// Memory plans: built-in and custom, and the sessions they drive.
final class PlanTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!

    private let romans = BookID("ROM")

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([
            Fixture.chapter(3, verseCount: 31, book: romans),
            Fixture.chapter(5, verseCount: 21, book: romans),
            Fixture.chapter(6, verseCount: 23, book: romans),
            Fixture.chapter(10, verseCount: 21, book: romans),
            Fixture.chapter(23, verseCount: 6, book: .psalms),
            // The walkthrough's demo plan lives here, so it can finish like any
            // other plan in these tests.
            Fixture.chapter(5, verseCount: 28, book: BookID("1TH")),
        ])
        report = ProgressReport(content: content, clock: clock)
    }

    private func target(_ plan: MemoryPlan, _ snapshot: ProgressSnapshot = ProgressSnapshot())
        -> MemoryTarget
    {
        report.target(for: plan, in: snapshot)
    }

    // MARK: - Built-in plans

    func testBuiltInPlansAreWellFormed() {
        XCTAssertFalse(BuiltInPlans.all.isEmpty)
        for plan in BuiltInPlans.all {
            XCTAssertTrue(plan.isBuiltIn, "\(plan.title)")
            XCTAssertFalse(plan.title.isEmpty)
            XCTAssertFalse(plan.summary.isEmpty, "\(plan.title) has no summary")
            XCTAssertFalse(plan.isEmpty, "\(plan.title) names no passages")
            for passage in plan.passages {
                XCTAssertLessThanOrEqual(passage.firstVerse, passage.lastVerse, "\(plan.title)")
                XCTAssertGreaterThan(passage.firstVerse, 0, "\(plan.title)")
            }
        }
    }

    func testBuiltInPlanIDsAreUnique() {
        let ids = BuiltInPlans.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTheRomanRoadIsTheFiveExpectedStops() {
        let refs = BuiltInPlans.romanRoad.declaredVerseRefs
        XCTAssertEqual(
            refs,
            [
                VerseRef(BookID("ROM"), 3, 23),
                VerseRef(BookID("ROM"), 6, 23),
                VerseRef(BookID("ROM"), 5, 8),
                VerseRef(BookID("ROM"), 10, 9),
                VerseRef(BookID("ROM"), 10, 10),
                VerseRef(BookID("ROM"), 10, 13),
            ],
            "the road is walked in its traditional order, not in canonical order"
        )
    }

    func testTheSermonOnTheMountCoversMatthewFiveToSeven() {
        let plan = BuiltInPlans.sermonOnTheMount
        let chapters = Set(plan.passages.map(\.chapter))
        XCTAssertEqual(chapters, [5, 6, 7])
        XCTAssertTrue(plan.passages.allSatisfy { $0.book == BookID("MAT") })
        XCTAssertGreaterThan(plan.sections.count, 1, "a long plan needs resting places")
    }

    /// The sections must tile Matthew 5–7 without gaps or repeats.
    func testTheSermonOnTheMountHasNoGapsOrOverlaps() {
        var byChapter: [Int: [Int]] = [:]
        for passage in BuiltInPlans.sermonOnTheMount.passages {
            byChapter[passage.chapter, default: []].append(contentsOf: passage.firstVerse...passage.lastVerse)
        }
        for (chapter, verses) in byChapter {
            XCTAssertEqual(
                verses, Array(verses.first!...verses.last!),
                "Matthew \(chapter) is not covered contiguously"
            )
            XCTAssertEqual(verses.first, 1, "Matthew \(chapter) does not start at verse 1")
        }
    }

    // MARK: - Targets built from plans

    func testAPlanBecomesAnOrderedTarget() {
        let target = target(BuiltInPlans.romanRoad)
        XCTAssertEqual(target.units.count, 6)
        XCTAssertEqual(target.units.first, VerseRef(romans, 3, 23))
        XCTAssertEqual(target.id, .plan(BuiltInPlans.romanRoad.id))
        XCTAssertEqual(target.title, "The Roman Road")
    }

    func testASingleSectionPlanIsOneBlock() {
        XCTAssertEqual(target(BuiltInPlans.romanRoad).blocks.count, 1)
    }

    func testASectionedPlanIsOneBlockPerSection() {
        let plan = MemoryPlan(
            id: "p",
            title: "Two parts",
            sections: [
                .init(id: "a", title: "First", passages: [PassageRef(romans, 3, 23)]),
                .init(id: "b", title: "Second", passages: [PassageRef(romans, 6, 23)]),
            ]
        )
        let target = target(plan)
        XCTAssertEqual(target.blocks.count, 2)
        XCTAssertEqual(target.blocks[0].title, "First")
        XCTAssertEqual(target.blocks[1].units, [VerseRef(romans, 6, 23)])
    }

    func testAPlanDropsVersesTheTranslationDoesNotCarry() {
        // Romans 3 has 31 verses in the fixture; asking for 40 must not invent one.
        let plan = MemoryPlan(id: "p", title: "Over the end", passages: [PassageRef(romans, 3, 30, 40)])
        XCTAssertEqual(target(plan).units, [VerseRef(romans, 3, 30), VerseRef(romans, 3, 31)])
    }

    func testAPlanNamingTheSameVerseTwiceMemorizesItOnce() {
        let plan = MemoryPlan(
            id: "p",
            title: "Repeated",
            passages: [PassageRef(romans, 3, 23), PassageRef(romans, 3, 23, 24)]
        )
        XCTAssertEqual(target(plan).units, [VerseRef(romans, 3, 23), VerseRef(romans, 3, 24)])
    }

    func testAnEmptyPlanProducesAnEmptyTarget() {
        let plan = MemoryPlan(id: "p", title: "Nothing", passages: [])
        XCTAssertTrue(target(plan).isEmpty)
        XCTAssertTrue(target(plan).blocks.isEmpty)
    }

    // MARK: - Plan progress shares verse mastery

    func testAVerseLearnedInAPlanIsLearnedInItsChapter() {
        var snapshot = ProgressSnapshot()
        snapshot.update(VerseRef(romans, 3, 23)) { state in
            state.status = .mastered
            state.masteredAt = clock.now
        }

        XCTAssertEqual(report.planProgress(BuiltInPlans.romanRoad, in: snapshot).masteredCount, 1)
        XCTAssertEqual(
            report.chapterProgress(ChapterRef(romans, 3), in: snapshot).masteredCount,
            1,
            "mastery is recorded against the verse, so the chapter sees it too"
        )
    }

    func testPlanProgressCountsOnlyItsOwnVerses() {
        var snapshot = ProgressSnapshot()
        for verse in 1...10 {
            snapshot.update(VerseRef(romans, 3, verse)) { $0.status = .mastered }
        }
        // Romans 3:23 is not among 1...10, so the plan has learned nothing.
        XCTAssertEqual(report.planProgress(BuiltInPlans.romanRoad, in: snapshot).masteredCount, 0)
    }

    func testAPlanIsCompleteOnlyAfterItsRecitation() {
        var snapshot = ProgressSnapshot()
        for ref in target(BuiltInPlans.romanRoad).units {
            snapshot.seedWorked(ref, by: .plan(BuiltInPlans.romanRoad.id), at: clock.now)
        }
        XCTAssertFalse(report.planProgress(BuiltInPlans.romanRoad, in: snapshot).isComplete)

        snapshot.confirmedPlanBlocks[BuiltInPlans.romanRoad.id] = [0]
        XCTAssertTrue(report.planProgress(BuiltInPlans.romanRoad, in: snapshot).isComplete)
    }

    // MARK: - Sessions over a plan

    func testASessionRunsAPlanLikeAnyOtherTarget() throws {
        var snapshot = ProgressSnapshot()
        let engine = SessionEngine(
            target: target(BuiltInPlans.romanRoad, snapshot),
            snapshot: snapshot,
            clock: clock
        )
        XCTAssertEqual(engine.step, .read(VerseRef(romans, 3, 23)))
        engine.takeVerseToMastered()
        XCTAssertEqual(
            engine.step,
            .cumulative(units: [VerseRef(romans, 3, 23)], after: VerseRef(romans, 3, 23))
        )
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .read(VerseRef(romans, 6, 23)), "on to the next stop")
        snapshot = engine.snapshot
        XCTAssertEqual(snapshot.currentTarget, .plan(BuiltInPlans.romanRoad.id))
    }

    func testAPlanCumulativePassCoversTheVersesSoFarInPlanOrder() {
        var snapshot = ProgressSnapshot()
        let plan = BuiltInPlans.romanRoad
        for ref in [VerseRef(romans, 3, 23), VerseRef(romans, 6, 23)] {
            snapshot.seedWorked(ref, by: .plan(plan.id), at: clock.now)
        }
        snapshot.planCumulativeProgress[plan.id] = 1

        let engine = SessionEngine(target: target(plan, snapshot), snapshot: snapshot, clock: clock)
        XCTAssertEqual(
            engine.step,
            .cumulative(
                units: [VerseRef(romans, 3, 23), VerseRef(romans, 6, 23)],
                after: VerseRef(romans, 6, 23)
            ),
            "the block follows plan order, not canonical order"
        )
    }

    func testFinishingAPlanRecordsItsCompletion() {
        var snapshot = ProgressSnapshot()
        let plan = BuiltInPlans.romanRoad
        let units = target(plan).units
        for ref in units {
            snapshot.seedWorked(ref, by: .plan(plan.id), at: clock.now)
        }
        snapshot.planCumulativeProgress[plan.id] = units.count

        let engine = SessionEngine(target: target(plan, snapshot), snapshot: snapshot, clock: clock)
        XCTAssertEqual(engine.step, .recitation(blockIndex: 0))
        engine.confirmCurrentStep()
        XCTAssertEqual(engine.step, .done)
        XCTAssertEqual(engine.snapshot.completedPlans[plan.id], clock.now)
    }

    /// Every kind of plan finishes through the same engine, so one celebration
    /// path covers the built-in ones, the user's own, one someone shared, and
    /// the walkthrough's demo.
    func testFinishingAnyPlanLeavesACelebrationOwed() {
        let shared = MemoryPlan(
            id: "from-marta", title: "What Marta sent",
            passages: [PassageRef(romans, 3, 23)], origin: .shared
        )
        let plans = [BuiltInPlans.romanRoad, BuiltInPlans.walkthrough, shared]
        for plan in plans {
            var snapshot = ProgressSnapshot()
            snapshot.customPlans = [shared]
            let units = target(plan, snapshot).units
            guard !units.isEmpty else { continue }
            for ref in units { snapshot.seedWorked(ref, by: .plan(plan.id), at: clock.now) }
            snapshot.planCumulativeProgress[plan.id] = units.count

            let engine = SessionEngine(
                target: target(plan, snapshot), snapshot: snapshot, clock: clock
            )
            XCTAssertNil(engine.snapshot.pendingCelebration, "\(plan.title): not finished yet")
            while case .recitation = engine.step { engine.confirmCurrentStep() }
            XCTAssertEqual(
                engine.snapshot.pendingCelebration, .plan(plan.id),
                "\(plan.title) finished without asking for its celebration"
            )
        }
    }

    // MARK: - Custom plans

    func testCustomPlansAppearAlongsideBuiltInOnes() {
        var snapshot = ProgressSnapshot()
        let mine = MemoryPlan(id: "mine", title: "My verses", passages: [PassageRef(.psalms, 23, 1)])
        snapshot.customPlans = [mine]

        let plans = report.plans(in: snapshot)
        XCTAssertEqual(plans.count, BuiltInPlans.all.count + 1)
        XCTAssertEqual(plans.last?.id, "mine")
        XCTAssertEqual(report.plan(id: "mine", in: snapshot)?.title, "My verses")
    }

    func testHidingABuiltInPlanRemovesItFromTheList() {
        var snapshot = ProgressSnapshot()
        snapshot.hiddenBuiltInPlans = [BuiltInPlans.romanRoad.id]
        XCTAssertFalse(report.plans(in: snapshot).contains { $0.id == BuiltInPlans.romanRoad.id })
        XCTAssertNotNil(
            report.plan(id: BuiltInPlans.romanRoad.id, in: snapshot),
            "a hidden plan is still resolvable, so old progress still reads"
        )
    }

    // MARK: - Activation

    func testBrowsingAPlanNeverPutsItOnTheHomePage() {
        var snapshot = ProgressSnapshot()
        // Every verse of the road learned elsewhere. The user has still never
        // said they are memorizing this plan, so it is not theirs to continue.
        for ref in target(BuiltInPlans.romanRoad).units {
            snapshot.update(ref) { $0.status = .mastered }
        }
        XCTAssertTrue(report.activePlans(in: snapshot).isEmpty)
    }

    func testAnActivatedPlanIsOfferedToContinue() {
        var snapshot = ProgressSnapshot()
        snapshot.activePlans = [BuiltInPlans.romanRoad.id]
        XCTAssertEqual(report.activePlans(in: snapshot).map(\.id), [BuiltInPlans.romanRoad.id])
    }

    func testAFinishedPlanIsNoLongerOfferedToContinue() {
        var snapshot = ProgressSnapshot()
        let plan = BuiltInPlans.romanRoad
        snapshot.activePlans = [plan.id]
        for ref in target(plan).units {
            snapshot.seedWorked(ref, by: .plan(plan.id), at: clock.now)
        }
        snapshot.confirmedPlanBlocks[plan.id] = [0]

        XCTAssertTrue(report.planProgress(plan, in: snapshot).isComplete)
        XCTAssertTrue(report.activePlans(in: snapshot).isEmpty, "finished plans move to Completed")
    }

    func testAHiddenPlanIsNotOfferedEvenIfItWasOnceActive() {
        var snapshot = ProgressSnapshot()
        snapshot.activePlans = [BuiltInPlans.romanRoad.id]
        snapshot.hiddenBuiltInPlans = [BuiltInPlans.romanRoad.id]
        XCTAssertTrue(report.activePlans(in: snapshot).isEmpty)
    }

    func testACustomPlanCanSpanBooks() {
        let plan = MemoryPlan(
            id: "mix",
            title: "Across books",
            passages: [PassageRef(.psalms, 23, 1, 2), PassageRef(romans, 8, 1)]
        )
        let target = target(plan)
        XCTAssertEqual(target.units.first?.book, .psalms)
        XCTAssertTrue(target.chapterRefs.contains(ChapterRef(.psalms, 23)))
    }
}
