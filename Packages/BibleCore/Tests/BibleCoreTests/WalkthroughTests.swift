import XCTest

@testable import BibleCore

/// The first-run walkthrough and its demo plan.
final class WalkthroughTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!

    private let thessalonians = BookID("1TH")

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([Fixture.chapter(5, verseCount: 28, book: thessalonians)])
        report = ProgressReport(content: content, clock: clock)
    }

    private var demoID: String { BuiltInPlans.walkthroughID }

    // MARK: - Offering it

    func testOfferedOnFirstLaunchOnly() {
        var progress = ProgressSnapshot()
        XCTAssertTrue(progress.onboarding.shouldOfferOnLaunch)

        progress.onboarding.hasBeenOffered = true
        XCTAssertFalse(progress.onboarding.shouldOfferOnLaunch, "asked once, not every launch")
    }

    func testAFreshUserIsNotMidWalkthrough() {
        XCTAssertFalse(ProgressSnapshot().onboarding.isActive)
        XCTAssertFalse(ProgressSnapshot().onboarding.hasCompleted)
    }

    // MARK: - The demo plan appears only during the walkthrough

    func testTheDemoIsHiddenBeforeAndAfter() {
        let progress = ProgressSnapshot()
        XCTAssertFalse(report.plans(in: progress).contains { $0.id == demoID })

        let finished = report.endingWalkthrough(report.startingWalkthrough(progress))
        XCTAssertFalse(
            report.plans(in: finished).contains { $0.id == demoID },
            "the demo exists only for the walkthrough"
        )
    }

    func testTheDemoLeadsTheListWhileRunning() {
        let running = report.startingWalkthrough(ProgressSnapshot())
        XCTAssertEqual(report.plans(in: running).first?.id, demoID)
    }

    func testTheDemoIsStillResolvableWhenNotListed() {
        // Progress recorded against it has to keep reading after it is hidden.
        XCTAssertNotNil(report.plan(id: demoID, in: ProgressSnapshot()))
    }

    func testTheDemoIsTwoShortVerses() throws {
        let target = report.target(for: BuiltInPlans.walkthrough, in: ProgressSnapshot())
        XCTAssertEqual(target.units.count, 2)
        XCTAssertEqual(
            target.units,
            [VerseRef(thessalonians, 5, 16), VerseRef(thessalonians, 5, 17)]
        )
    }

    // MARK: - Running it

    func testStartingMarksItOfferedAndActive() {
        let running = report.startingWalkthrough(ProgressSnapshot())
        XCTAssertTrue(running.onboarding.isActive)
        XCTAssertTrue(running.onboarding.hasBeenOffered)
    }

    func testStartingAgainClearsThePreviousRun() {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        let target = report.target(for: BuiltInPlans.walkthrough, in: progress)
        for ref in target.units { progress.seedWorked(ref, by: .plan(demoID), at: clock.now) }
        progress.confirmedPlanBlocks[demoID] = [0]
        progress.completedPlans[demoID] = clock.now

        let restarted = report.startingWalkthrough(progress)
        XCTAssertTrue(
            report.planProgress(BuiltInPlans.walkthrough, in: restarted).coveredCount == 0,
            "a second run must demonstrate the same thing as the first"
        )
        XCTAssertNil(restarted.completedPlans[demoID])
    }

    func testTheDemoRunsLikeAnyOtherPlan() {
        let progress = report.startingWalkthrough(ProgressSnapshot())
        let engine = SessionEngine(
            target: report.target(for: BuiltInPlans.walkthrough, in: progress),
            snapshot: progress,
            clock: clock
        )
        XCTAssertEqual(engine.step, .read(VerseRef(thessalonians, 5, 16)))
        engine.takeVerseToMastered()
        engine.confirmCurrentStep()  // cumulative
        XCTAssertEqual(engine.step, .read(VerseRef(thessalonians, 5, 17)))
    }

    func testFinishingTheDemoCompletesThePlan() {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        let engine = SessionEngine(
            target: report.target(for: BuiltInPlans.walkthrough, in: progress),
            snapshot: progress,
            clock: clock
        )
        var guardCount = 0
        while engine.step != .done, guardCount < 60 {
            engine.confirmCurrentStep()
            guardCount += 1
        }
        XCTAssertLessThan(guardCount, 60, "the demo session did not terminate")
        progress = engine.snapshot
        XCTAssertTrue(report.planProgress(BuiltInPlans.walkthrough, in: progress).isComplete)
    }

    // MARK: - Ending it

    func testCompletingItRecordsThat() {
        let done = report.endingWalkthrough(report.startingWalkthrough(ProgressSnapshot()))
        XCTAssertFalse(done.onboarding.isActive)
        XCTAssertTrue(done.onboarding.hasCompleted)
        XCTAssertTrue(done.onboarding.hasBeenOffered)
    }

    func testSkippingLeavesItDoneRatherThanUnfinished() {
        // Leaving part-way through is a decision about whether the tour is
        // useful. Recording it as unfinished only earns the user more
        // prompting; Settings starts it over for anyone who wants it.
        let skipped = report.endingWalkthrough(report.startingWalkthrough(ProgressSnapshot()))
        XCTAssertFalse(skipped.onboarding.isActive)
        XCTAssertTrue(skipped.onboarding.hasCompleted)
        XCTAssertTrue(skipped.onboarding.hasBeenOffered, "so it is not offered again unprompted")
    }

    /// The demo goes; what the user actually learned does not.
    func testTheVersesLearnedInTheDemoStayMemorized() {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        let target = report.target(for: BuiltInPlans.walkthrough, in: progress)
        for ref in target.units { progress.seedWorked(ref, by: .plan(demoID), at: clock.now) }

        let done = report.endingWalkthrough(progress)
        for ref in target.units {
            XCTAssertEqual(done.state(for: ref).status, .mastered, "\(ref) was really learned")
        }
        XCTAssertEqual(report.chapterProgress(ChapterRef(thessalonians, 5), in: done).masteredCount, 2)
    }

    func testEndingItMovesTheResumePointOffTheDemo() {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        progress.currentTarget = .plan(demoID)

        let done = report.endingWalkthrough(progress)
        XCTAssertNotEqual(
            done.currentTarget, .plan(demoID),
            "Continue must not point at a plan that no longer exists"
        )
    }

    func testEndingItLeavesOtherPlansAlone() {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        progress.customPlans = [MemoryPlan(id: "mine", title: "Mine", passages: [PassageRef(thessalonians, 5, 1)])]

        let done = report.endingWalkthrough(progress)
        XCTAssertEqual(done.customPlans.map(\.id), ["mine"])
        XCTAssertTrue(report.plans(in: done).contains { $0.id == "mine" })
    }

    func testOnboardingStateSurvivesEncoding() throws {
        var progress = report.startingWalkthrough(ProgressSnapshot())
        progress.onboarding.hasCompleted = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ProgressSnapshot.self, from: encoder.encode(progress))
        XCTAssertEqual(restored.onboarding, progress.onboarding)
    }

    func testOlderProgressFilesDefaultToHavingBeenOffered() throws {
        // A file written before the walkthrough existed has no onboarding key.
        // It decodes as "not yet offered", so an existing user is shown the
        // walkthrough once — which is the friendlier of the two mistakes.
        let json = #"{"schemaVersion":4,"verseStates":{},"chapterStates":{}}"#
        let progress = try JSONDecoder().decode(ProgressSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(progress.onboarding.isActive)
        XCTAssertTrue(progress.onboarding.shouldOfferOnLaunch)
    }
}
