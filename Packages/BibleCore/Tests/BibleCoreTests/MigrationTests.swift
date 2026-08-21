import XCTest

@testable import BibleCore

/// Progress migration across every schema the app has shipped.
///
/// Schema 1 → 2 dropped the provisional verse state; 2 → 3 re-keyed everything
/// from psalm numbers to whole-Bible verse references. Both run against real
/// payloads, because the only thing that matters is that somebody who has been
/// using the app loses nothing.
final class MigrationTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var clock: TestClock!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("psalms-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("progress.json")
        clock = TestClock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> ProgressStore { ProgressStore(fileURL: fileURL, clock: clock) }

    private func write(_ json: String) throws {
        try json.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Schema 2: psalm-number keys, no provisional state, Psalm 23 finished and
    /// Psalm 1 part-way.
    private func writeVersionTwoFile() throws {
        try write(
            """
            {
              "schemaVersion": 2,
              "translationId": "bsb",
              "currentPsalm": 1,
              "currentVerse": 4,
              "lastOpenedAt": "2026-08-18T09:00:00Z",
              "notificationsEnabled": true,
              "includeSuperscriptions": false,
              "reminderTime": { "hour": 6, "minute": 30 },
              "psalmStates": {
                "23": {
                  "psalmNumber": 23,
                  "fullRecitationConfirmed": true,
                  "cumulativeConfirmedThrough": 6,
                  "confirmedStanzas": [],
                  "completedAt": "2026-08-17T10:00:00Z",
                  "verseStates": {
                    "1": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":1,
                          "masteredAt":"2026-08-17T09:30:00Z"},
                    "2": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-17T09:35:00Z"},
                    "3": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-17T09:40:00Z"},
                    "4": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-17T09:45:00Z"},
                    "5": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-17T09:50:00Z"},
                    "6": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-17T09:55:00Z"}
                  }
                },
                "1": {
                  "psalmNumber": 1,
                  "fullRecitationConfirmed": false,
                  "cumulativeConfirmedThrough": 3,
                  "confirmedStanzas": [],
                  "verseStates": {
                    "1": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":2,
                          "masteredAt":"2026-08-18T09:10:00Z"},
                    "2": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-18T09:15:00Z"},
                    "3": {"status":"mastered","highestMaskLevelCleared":4,"readCount":3,"peekCount":0,
                          "masteredAt":"2026-08-18T09:20:00Z"},
                    "4": {"status":"inProgress","highestMaskLevelCleared":2,"readCount":3,"peekCount":1}
                  }
                }
              }
            }
            """
        )
    }

    // MARK: - Schema 2 → 3

    func testVersionTwoFileLoadsWithoutRecovery() throws {
        try writeVersionTwoFile()
        let store = makeStore()
        _ = store.load()
        XCTAssertEqual(store.lastLoadOutcome, .loaded, "a v2 file must not be quarantined")
    }

    func testPsalmNumbersBecomeVerseReferences() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()

        XCTAssertEqual(progress.state(for: VerseRef(.psalms, 23, 1)).status, .mastered)
        XCTAssertEqual(progress.state(for: VerseRef(.psalms, 23, 1)).peekCount, 1)
        XCTAssertEqual(progress.state(for: VerseRef(.psalms, 1, 4)).status, .inProgress)
        XCTAssertEqual(progress.state(for: VerseRef(.psalms, 1, 4)).highestMaskLevelCleared, 2)
    }

    func testNoVerseOfWorkIsLost() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()
        XCTAssertEqual(progress.verseStates.count, 10, "six in Psalm 23, four in Psalm 1")
        XCTAssertEqual(progress.verseStates.values.filter(\.isMastered).count, 9)
    }

    func testChapterStateMovesAcross() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()

        let psalm23 = progress.state(for: ChapterRef(.psalms, 23))
        XCTAssertTrue(psalm23.fullRecitationConfirmed)
        XCTAssertEqual(psalm23.cumulativeConfirmedThrough, 6)
        XCTAssertNotNil(psalm23.completedAt)

        let psalm1 = progress.state(for: ChapterRef(.psalms, 1))
        XCTAssertFalse(psalm1.fullRecitationConfirmed)
        XCTAssertEqual(psalm1.cumulativeConfirmedThrough, 3)
    }

    func testAFinishedPsalmIsStillFinishedAfterMigrating() throws {
        try writeVersionTwoFile()
        let content = try Fixture.store([Fixture.chapter(23, verseCount: 6, book: .psalms)])
        let report = ProgressReport(content: content, clock: clock)

        let psalm23 = report.chapterProgress(ChapterRef(.psalms, 23), in: makeStore().load())
        XCTAssertTrue(psalm23.isMemorized, "a completed psalm must survive the move intact")
        XCTAssertEqual(psalm23.masteredCount, 6)
    }

    func testTheResumePointMovesAcross() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()
        XCTAssertEqual(progress.currentTarget, .chapter(ChapterRef(.psalms, 1)))
        XCTAssertEqual(progress.currentVerse, VerseRef(.psalms, 1, 4))
    }

    func testSettingsMoveAcross() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()
        XCTAssertTrue(progress.notificationsEnabled)
        XCTAssertEqual(progress.reminderTime, ReminderTime(hour: 6, minute: 30))
    }

    func testTheFileIsRewrittenAtTheCurrentVersion() throws {
        try writeVersionTwoFile()
        let store = makeStore()
        try store.save(store.load())

        let data = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, ProgressSnapshot.currentSchemaVersion)
        XCTAssertNil(json["psalmStates"], "the old shape must not linger")
        let verses = try XCTUnwrap(json["verseStates"] as? [String: Any])
        XCTAssertNotNil(verses["PSA 23:1"], "keys are now references")
    }

    func testMigrationIsIdempotent() throws {
        try writeVersionTwoFile()
        let first = makeStore().load()
        try makeStore().save(first)
        XCTAssertEqual(makeStore().load(), first)
    }

    // MARK: - Schema 3 → 4: coverage split from mastery

    func testMasteredVersesAreBackfilledAsCoveredByTheirChapter() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()
        // Before coverage existed, mastery *was* coverage, so a finished psalm
        // must not reopen asking about every verse it already taught.
        XCTAssertTrue(progress.isCovered(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23))))
        XCTAssertEqual(
            progress.coveredCount(
                for: .chapter(ChapterRef(.psalms, 23)),
                among: (1...6).map { VerseRef(.psalms, 23, $0) }
            ),
            6
        )
    }

    func testAFinishedPsalmStaysFinishedAcrossTheCoverageSplit() throws {
        try writeVersionTwoFile()
        let content = try Fixture.store([Fixture.chapter(23, verseCount: 6, book: .psalms)])
        let report = ProgressReport(content: content, clock: clock)
        XCTAssertTrue(report.chapterProgress(ChapterRef(.psalms, 23), in: makeStore().load()).isMemorized)
    }

    func testWorkedChaptersAreBackfilledAsStarted() throws {
        try writeVersionTwoFile()
        let progress = makeStore().load()
        XCTAssertNotNil(
            progress.state(for: ChapterRef(.psalms, 1)).startedAt,
            "a chapter with work in it was worked as a chapter, back when that was the only way"
        )
    }

    // MARK: - Schema 1 → 4, in one step

    func testAVersionOneFileMigratesAllTheWay() throws {
        try write(
            """
            {
              "schemaVersion": 1,
              "currentPsalm": 23,
              "psalmStates": {
                "23": {"psalmNumber":23,"verseStates":{
                  "1": {"status":"provisional","highestMaskLevelCleared":4,"readCount":3,
                        "provisionalAt":"2026-08-18T09:10:00Z"}
                }}
              }
            }
            """
        )
        let progress = makeStore().load()
        let verse = progress.state(for: VerseRef(.psalms, 23, 1))
        XCTAssertEqual(verse.status, .mastered, "provisional promoted, then re-keyed")
        XCTAssertEqual(verse.masteredAt, ISO8601DateFormatter().date(from: "2026-08-18T09:10:00Z"))
        XCTAssertEqual(progress.currentTarget, .chapter(ChapterRef(.psalms, 23)))
        XCTAssertTrue(
            progress.isCovered(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23))),
            "provisional promoted, re-keyed, and credited as chapter work"
        )
    }

    // MARK: - Round-tripping the new shape

    func testTheNewShapeRoundTrips() throws {
        var progress = ProgressSnapshot()
        progress.currentTarget = .plan("builtin.roman-road")
        progress.currentVerse = VerseRef(BookID("ROM"), 3, 23)
        progress.update(VerseRef(BookID("ROM"), 3, 23)) { state in
            state.status = .mastered
            state.masteredAt = self.clock.now
            state.peekCount = 2
        }
        progress.update(ChapterRef(BookID("ROM"), 3)) { $0.cumulativeConfirmedThrough = 23 }
        progress.customPlans = [
            MemoryPlan(id: "mine", title: "Mine", passages: [PassageRef(.psalms, 23, 1, 6)])
        ]
        progress.hiddenBuiltInPlans = ["builtin.lords-prayer"]
        progress.confirmedPlanBlocks["builtin.roman-road"] = [0]
        progress.planCumulativeProgress["builtin.roman-road"] = 3
        progress.completedPlans["mine"] = clock.now

        try makeStore().save(progress)
        XCTAssertEqual(makeStore().load(), progress)
    }

    func testAnUnreadableFileIsQuarantinedRatherThanLosingTheApp() throws {
        try write("{ not json at all")
        let store = makeStore()
        let progress = store.load()
        guard case .recovered = store.lastLoadOutcome else {
            return XCTFail("expected recovery, got \(store.lastLoadOutcome)")
        }
        XCTAssertTrue(progress.verseStates.isEmpty)
    }
}
