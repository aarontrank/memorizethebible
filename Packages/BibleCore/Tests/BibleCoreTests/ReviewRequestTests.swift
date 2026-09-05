import XCTest

@testable import BibleCore

/// When the app has earned the right to ask what someone thinks of it.
///
/// Apple's own prompt does the asking, and the system decides whether to show
/// it at all. What this app decides is the *moment*: it has to be one where the
/// user has just done something they chose to do and finished.
final class ReviewRequestTests: XCTestCase {
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
            Fixture.chapter(5, verseCount: 28, book: BookID("1TH")),
        ])
        report = ProgressReport(content: content, clock: clock)
    }

    // MARK: - Not yet

    func testAFreshUserIsNotAsked() {
        XCTAssertFalse(report.hasEarnedReviewRequest(in: ProgressSnapshot()))
    }

    func testMemorizingVersesWithoutFinishingAPlanIsNotEnough() {
        var progress = ProgressSnapshot()
        for verse in 1...6 {
            progress.seedWorked(VerseRef(.psalms, 23, verse), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        }
        XCTAssertFalse(
            report.hasEarnedReviewRequest(in: progress),
            "a chapter is good work, but the ask is tied to plans"
        )
    }

    /// The demo is two verses long and the app put it there. Finishing it says
    /// nothing about whether someone likes the app enough to say so publicly.
    func testFinishingTheWalkthroughDemoIsNotEnough() {
        var progress = ProgressSnapshot()
        progress.completedPlans[BuiltInPlans.walkthroughID] = clock.now
        XCTAssertFalse(report.hasEarnedReviewRequest(in: progress))
    }

    /// Being handed a plan is not the same as making one.
    func testKeepingAPlanSomeoneSentIsNotEnough() {
        var progress = ProgressSnapshot()
        progress.customPlans = [
            MemoryPlan(
                id: "from-marta", title: "What Marta sent",
                passages: [PassageRef(romans, 3, 23)], origin: .shared
            )
        ]
        XCTAssertFalse(report.hasEarnedReviewRequest(in: progress))
    }

    // MARK: - Earned

    func testFinishingARealPlanEarnsIt() {
        var progress = ProgressSnapshot()
        progress.completedPlans[BuiltInPlans.romanRoad.id] = clock.now
        XCTAssertTrue(report.hasEarnedReviewRequest(in: progress))
    }

    func testBuildingAPlanOfYourOwnEarnsIt() {
        var progress = ProgressSnapshot()
        progress.customPlans = [
            MemoryPlan(id: "mine", title: "Mine", passages: [PassageRef(.psalms, 23, 1, 6)])
        ]
        XCTAssertTrue(
            report.hasEarnedReviewRequest(in: progress),
            "building one is a vote of confidence on its own — it need not be finished"
        )
    }

    func testFinishingAPlanSomeoneSentEarnsIt() {
        var progress = ProgressSnapshot()
        progress.customPlans = [
            MemoryPlan(
                id: "from-marta", title: "What Marta sent",
                passages: [PassageRef(romans, 3, 23)], origin: .shared
            )
        ]
        progress.completedPlans["from-marta"] = clock.now
        XCTAssertTrue(report.hasEarnedReviewRequest(in: progress), "they still finished it")
    }

    /// The walkthrough alongside a real plan must not mask the real one.
    func testTheDemoDoesNotHideARealPlanFinishedBesideIt() {
        var progress = ProgressSnapshot()
        progress.completedPlans[BuiltInPlans.walkthroughID] = clock.now
        progress.completedPlans["builtin.lords-prayer"] = clock.now
        XCTAssertTrue(report.hasEarnedReviewRequest(in: progress))
    }

    // MARK: - Asked once, and only once

    func testAFreshUserHasNotBeenAsked() {
        XCTAssertFalse(ProgressSnapshot().hasAskedForReview)
    }

    func testHavingBeenAskedSurvivesQuittingTheApp() throws {
        var progress = ProgressSnapshot()
        progress.hasAskedForReview = true

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(ProgressSnapshot.self, from: encoder.encode(progress))
        XCTAssertTrue(
            restored.hasAskedForReview,
            "asking again on the next launch is exactly what must not happen"
        )
    }

    func testProgressWrittenBeforeThisExistedReadsAsNotYetAsked() throws {
        let json = #"{"schemaVersion":5,"verseStates":{},"chapterStates":{}}"#
        let progress = try JSONDecoder().decode(ProgressSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(progress.hasAskedForReview)
    }
}
