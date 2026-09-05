import XCTest

@testable import BibleCore

/// Milestones: what has been earned, and the order it was earned in.
///
/// They are derived from the work already recorded rather than written down as
/// they happen, so someone who has been using the app for months has their
/// whole history the first time this ships, rather than starting from empty.
final class MilestoneTests: XCTestCase {
    private var clock: TestClock!
    private var content: ContentStore!
    private var report: ProgressReport!

    private let romans = BookID("ROM")
    /// Two chapters, so a whole book is reachable in a test.
    private let jude = BookID("JUD")

    override func setUpWithError() throws {
        clock = TestClock()
        content = try Fixture.store([
            Fixture.chapter(23, verseCount: 6, book: .psalms),
            Fixture.chapter(1, verseCount: 4, book: jude),
            Fixture.chapter(2, verseCount: 3, book: jude),
            Fixture.chapter(3, verseCount: 31, book: romans),
            Fixture.chapter(5, verseCount: 21, book: romans),
            Fixture.chapter(6, verseCount: 23, book: romans),
            Fixture.chapter(10, verseCount: 21, book: romans),
        ])
        report = ProgressReport(content: content, clock: clock)
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 86_400 * Double(n)) }

    private func master(_ refs: [VerseRef], from day: Int, in progress: inout ProgressSnapshot) {
        for (offset, ref) in refs.enumerated() {
            progress.update(ref) { state in
                state.status = .mastered
                state.masteredAt = self.day(day + offset)
            }
        }
    }

    private func psalm23(_ verse: Int) -> VerseRef { VerseRef(.psalms, 23, verse) }

    /// Memorized properly: every unit worked in the chapter and recited.
    private func memorizeChapter(
        _ ref: ChapterRef, verses: Int, on day: Int, in progress: inout ProgressSnapshot
    ) {
        for verse in 1...verses {
            let verseRef = VerseRef(ref.book, ref.chapter, verse)
            progress.update(verseRef) { state in
                state.status = .mastered
                state.masteredAt = self.day(day)
            }
            progress.markCovered(verseRef, by: .chapter(ref))
        }
        progress.update(ref) { state in
            state.startedAt = self.day(day)
            state.fullRecitationConfirmed = true
            state.completedAt = self.day(day)
        }
    }

    // MARK: - Nothing yet

    func testAFreshUserHasNoMilestones() {
        XCTAssertTrue(report.milestones(in: ProgressSnapshot()).isEmpty)
    }

    func testAVerseInProgressEarnsNothing() {
        var progress = ProgressSnapshot()
        progress.update(psalm23(1)) { $0.status = .inProgress }
        XCTAssertTrue(report.milestones(in: progress).isEmpty)
    }

    // MARK: - Counting verses

    func testTheFirstVerseIsAMilestone() {
        var progress = ProgressSnapshot()
        master([psalm23(1)], from: 5, in: &progress)

        let milestones = report.milestones(in: progress)
        XCTAssertEqual(milestones.map(\.kind), [.firstVerse])
        XCTAssertEqual(milestones.first?.achievedAt, day(5))
    }

    func testTenVersesIsEarnedOnTheTenth() {
        var progress = ProgressSnapshot()
        let refs = (1...10).map { VerseRef(romans, 3, $0) }
        master(refs, from: 1, in: &progress)

        let milestones = report.milestones(in: progress)
        XCTAssertEqual(milestones.map(\.kind), [.firstVerse, .tenVerses])
        XCTAssertEqual(milestones.first?.achievedAt, day(1), "the first verse, not the tenth")
        XCTAssertEqual(milestones.last?.achievedAt, day(10), "dated the day the tenth landed")
    }

    func testNineVersesIsNotTen() {
        var progress = ProgressSnapshot()
        master((1...9).map { VerseRef(romans, 3, $0) }, from: 1, in: &progress)
        XCTAssertEqual(report.milestones(in: progress).map(\.kind), [.firstVerse])
    }

    func testAHundredVerses() {
        var progress = ProgressSnapshot()
        // 31 + 21 + 23 + 21 = 96 in Romans, plus 4 of Jude 1.
        var refs = (1...31).map { VerseRef(romans, 3, $0) }
        refs += (1...21).map { VerseRef(romans, 5, $0) }
        refs += (1...23).map { VerseRef(romans, 6, $0) }
        refs += (1...21).map { VerseRef(romans, 10, $0) }
        refs += (1...4).map { VerseRef(jude, 1, $0) }
        XCTAssertEqual(refs.count, 100)
        master(refs, from: 1, in: &progress)

        let hundred = report.milestones(in: progress).first { $0.kind == .hundredVerses }
        XCTAssertEqual(hundred?.achievedAt, day(100))
    }

    /// A verse mastered before the app recorded dates cannot be placed in a
    /// sequence, so it is not counted towards one.
    func testAnUndatedMasteryDoesNotCountTowardsATotal() {
        var progress = ProgressSnapshot()
        progress.update(psalm23(1)) { $0.status = .mastered }
        XCTAssertTrue(report.milestones(in: progress).isEmpty)
    }

    // MARK: - Chapters, books and plans

    func testAWholeChapterIsAMilestoneNamingTheChapter() {
        var progress = ProgressSnapshot()
        memorizeChapter(ChapterRef(.psalms, 23), verses: 6, on: 3, in: &progress)

        let chapter = report.milestones(in: progress).first { $0.kind == .firstChapter }
        XCTAssertEqual(chapter?.achievedAt, day(3))
        XCTAssertEqual(chapter?.subject, "Psalm 23")
    }

    func testTheEarliestChapterIsTheOneThatCounts() {
        var progress = ProgressSnapshot()
        memorizeChapter(ChapterRef(jude, 2), verses: 3, on: 20, in: &progress)
        memorizeChapter(ChapterRef(.psalms, 23), verses: 6, on: 8, in: &progress)

        let chapter = report.milestones(in: progress).first { $0.kind == .firstChapter }
        XCTAssertEqual(chapter?.achievedAt, day(8))
        XCTAssertEqual(chapter?.subject, "Psalm 23")
    }

    func testAWholeBookIsEarnedWhenItsLastChapterLands() {
        var progress = ProgressSnapshot()
        memorizeChapter(ChapterRef(jude, 1), verses: 4, on: 4, in: &progress)
        memorizeChapter(ChapterRef(jude, 2), verses: 3, on: 9, in: &progress)

        let book = report.milestones(in: progress).first { $0.kind == .firstBook }
        XCTAssertEqual(book?.achievedAt, day(9), "the day the book was finished, not started")
        XCTAssertEqual(book?.subject, "Test Book")
    }

    func testHalfABookIsNotABook() {
        var progress = ProgressSnapshot()
        memorizeChapter(ChapterRef(jude, 1), verses: 4, on: 4, in: &progress)
        XCTAssertNil(report.milestones(in: progress).first { $0.kind == .firstBook })
    }

    func testAWholePlanIsAMilestoneNamingThePlan() {
        var progress = ProgressSnapshot()
        progress.completedPlans[BuiltInPlans.romanRoad.id] = day(12)

        let plan = report.milestones(in: progress).first { $0.kind == .firstPlan }
        XCTAssertEqual(plan?.achievedAt, day(12))
        XCTAssertEqual(plan?.subject, "The Roman Road")
    }

    /// Two verses the app handed them is not a plan they took on.
    func testTheWalkthroughDemoIsNotAWholePlan() {
        var progress = ProgressSnapshot()
        progress.completedPlans[BuiltInPlans.walkthroughID] = day(2)
        XCTAssertNil(report.milestones(in: progress).first { $0.kind == .firstPlan })
    }

    func testEachMilestoneIsEarnedOnlyOnce() {
        var progress = ProgressSnapshot()
        memorizeChapter(ChapterRef(jude, 1), verses: 4, on: 4, in: &progress)
        memorizeChapter(ChapterRef(jude, 2), verses: 3, on: 9, in: &progress)
        progress.completedPlans[BuiltInPlans.romanRoad.id] = day(12)
        progress.completedPlans["builtin.lords-prayer"] = day(14)

        let kinds = report.milestones(in: progress).map(\.kind)
        XCTAssertEqual(Set(kinds).count, kinds.count, "no kind appears twice")
    }

    // MARK: - Order

    func testMilestonesComeBackInTheOrderTheyWereEarned() {
        var progress = ProgressSnapshot()
        // One chapter of a two-chapter book, so finishing it is not also a book.
        memorizeChapter(ChapterRef(jude, 1), verses: 4, on: 3, in: &progress)
        master((1...10).map { VerseRef(romans, 3, $0) }, from: 10, in: &progress)
        progress.completedPlans[BuiltInPlans.romanRoad.id] = day(30)

        XCTAssertEqual(
            report.milestones(in: progress).map(\.kind),
            [.firstVerse, .firstChapter, .tenVerses, .firstPlan],
            "the sequence they happened in, whatever kind they are"
        )
    }

    func testMilestonesEarnedOnTheSameDayHaveASettledOrder() {
        var progress = ProgressSnapshot()
        // The chapter and the tenth verse land together.
        memorizeChapter(ChapterRef(romans, 3), verses: 31, on: 7, in: &progress)
        XCTAssertEqual(
            report.milestones(in: progress).map(\.kind),
            [.firstVerse, .tenVerses, .firstChapter],
            "ties resolve by what each one takes, so the order never wobbles"
        )
    }
}
