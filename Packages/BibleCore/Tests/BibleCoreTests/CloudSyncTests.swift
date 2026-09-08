import XCTest

@testable import BibleCore

/// Reconciling two devices' copies of the record (§13.1).
///
/// The rule these all circle is the one that makes the setting safe to leave
/// on: work done is unioned, choices come from whoever chose most recently, and
/// nothing a person actually memorized can be dropped for being the older copy.
final class ProgressMergeTests: XCTestCase {
    private let clock = TestClock()
    private var psalm: ChapterRef { ChapterRef(.psalms, 23) }

    private func snapshot(updatedAt: Date) -> ProgressSnapshot {
        ProgressSnapshot(updatedAt: updatedAt)
    }

    // MARK: - Work done

    func testWorkFromBothDevicesSurvives() {
        let now = clock.now
        var phone = snapshot(updatedAt: now)
        phone.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(psalm), at: now)
        var ipad = snapshot(updatedAt: now.addingTimeInterval(60))
        ipad.seedWorked(VerseRef(.psalms, 23, 2), by: .chapter(psalm), at: now)

        let merged = ProgressMerge.merge(local: phone, remote: ipad)

        XCTAssertTrue(merged.state(for: VerseRef(.psalms, 23, 1)).isMastered)
        XCTAssertTrue(merged.state(for: VerseRef(.psalms, 23, 2)).isMastered)
        XCTAssertTrue(merged.isCovered(VerseRef(.psalms, 23, 1), by: .chapter(psalm)))
        XCTAssertTrue(merged.isCovered(VerseRef(.psalms, 23, 2), by: .chapter(psalm)))
    }

    /// The high-water mark inside a verse, applied across two devices: the
    /// further of the two stands, even when it is the older copy saying it.
    func testTheFurtherOfTheTwoStandsEvenFromTheOlderCopy() {
        let ref = VerseRef(.psalms, 23, 1)
        let now = clock.now
        var older = snapshot(updatedAt: now)
        older.update(ref) { state in
            state.status = .mastered
            state.highestMaskLevelCleared = 4
            state.readCount = 3
            state.masteredAt = now
        }
        var newer = snapshot(updatedAt: now.addingTimeInterval(3600))
        newer.update(ref) { state in
            state.status = .inProgress
            state.highestMaskLevelCleared = 2
            state.readCount = 3
            state.peekCount = 4
        }

        let merged = ProgressMerge.merge(local: newer, remote: older)

        XCTAssertEqual(merged.state(for: ref).status, .mastered)
        XCTAssertEqual(merged.state(for: ref).highestMaskLevelCleared, 4)
        XCTAssertEqual(merged.state(for: ref).masteredAt, now)
        // Counts take the higher, not the sum: two devices that each saw three
        // reads offline saw the same three reads.
        XCTAssertEqual(merged.state(for: ref).readCount, 3)
        XCTAssertEqual(merged.state(for: ref).peekCount, 4)
    }

    func testChapterRecitationsAreUnioned() {
        let now = clock.now
        var phone = snapshot(updatedAt: now)
        phone.update(psalm) { state in
            state.confirmedStanzas = [0]
            state.cumulativeConfirmedThrough = 3
            state.startedAt = now
        }
        var ipad = snapshot(updatedAt: now.addingTimeInterval(60))
        ipad.update(psalm) { state in
            state.confirmedStanzas = [1]
            state.cumulativeConfirmedThrough = 5
            state.startedAt = now.addingTimeInterval(-86_400)
        }

        let merged = ProgressMerge.merge(local: phone, remote: ipad)

        XCTAssertEqual(merged.state(for: psalm).confirmedStanzas, [0, 1])
        XCTAssertEqual(merged.state(for: psalm).cumulativeConfirmedThrough, 5)
        // When the work began, not when this device heard about it.
        XCTAssertEqual(merged.state(for: psalm).startedAt, now.addingTimeInterval(-86_400))
    }

    // MARK: - Choices

    func testAPlanTakenOffTheHomePageStaysOff() {
        let now = clock.now
        let older = ProgressSnapshot(activePlans: ["builtin.roman-road"], updatedAt: now)
        let newer = ProgressSnapshot(activePlans: [], updatedAt: now.addingTimeInterval(3600))

        XCTAssertEqual(ProgressMerge.merge(local: newer, remote: older).activePlans, [])
        XCTAssertEqual(ProgressMerge.merge(local: older, remote: newer).activePlans, [])
    }

    func testTheResumePointComesFromWhicheverDeviceWasUsedLast() {
        let now = clock.now
        var older = snapshot(updatedAt: now)
        older.currentTarget = .chapter(ChapterRef(.psalms, 1))
        older.currentVerse = VerseRef(.psalms, 1, 1)
        var newer = snapshot(updatedAt: now.addingTimeInterval(3600))
        newer.currentTarget = .chapter(psalm)
        newer.currentVerse = VerseRef(.psalms, 23, 4)

        let merged = ProgressMerge.merge(local: older, remote: newer)

        XCTAssertEqual(merged.currentTarget, .chapter(psalm))
        XCTAssertEqual(merged.currentVerse, VerseRef(.psalms, 23, 4))
    }

    /// A record that predates iCloud sync has no stamp at all, so it must never
    /// out-argue one that does.
    func testARecordFromBeforeSyncNeverWinsAnArgument() {
        var upgraded = snapshot(updatedAt: clock.now)
        upgraded.reminderTime = ReminderTime(hour: 6, minute: 30)
        var beforeSync = ProgressSnapshot()
        beforeSync.reminderTime = ReminderTime(hour: 21, minute: 0)

        XCTAssertEqual(
            ProgressMerge.merge(local: beforeSync, remote: upgraded).reminderTime,
            ReminderTime(hour: 6, minute: 30)
        )
    }

    // MARK: - What belongs to the device

    func testRemindersAndARunningTourBelongToTheDevice() {
        let now = clock.now
        let here = ProgressSnapshot(notificationsEnabled: false, updatedAt: now)
        var there = ProgressSnapshot(notificationsEnabled: true, updatedAt: now.addingTimeInterval(3600))
        there.onboarding.isActive = true
        there.onboarding.hasCompleted = true

        let merged = ProgressMerge.merge(local: here, remote: there)

        // Reminders rest on a permission granted on one device.
        XCTAssertFalse(merged.notificationsEnabled)
        XCTAssertFalse(merged.onboarding.isActive)
        // Having been through the tour is about the person, though, so a new
        // device set up from iCloud is not walked through the app again.
        XCTAssertTrue(merged.onboarding.hasCompleted)
    }

    func testTheAppOnlyEverAsksForAReviewOnce() {
        let now = clock.now
        var asked = snapshot(updatedAt: now)
        asked.hasAskedForReview = true
        let notAsked = snapshot(updatedAt: now.addingTimeInterval(3600))

        XCTAssertTrue(ProgressMerge.merge(local: notAsked, remote: asked).hasAskedForReview)
    }

    // MARK: - Plans

    func testADeletedPlanIsNotHandedBackByTheOtherDevice() {
        let now = clock.now
        let plan = MemoryPlan(
            id: "mine",
            title: "Verses for a hard week",
            passages: [PassageRef(.psalms, 23, 1, 6)],
            createdAt: now
        )
        let stillHasIt = ProgressSnapshot(customPlans: [plan], activePlans: ["mine"], updatedAt: now)
        var deletedIt = snapshot(updatedAt: now.addingTimeInterval(60))
        deletedIt.removedPlans[plan.id] = now.addingTimeInterval(60)

        let merged = ProgressMerge.merge(local: deletedIt, remote: stillHasIt)

        XCTAssertTrue(merged.customPlans.isEmpty)
        XCTAssertFalse(merged.activePlans.contains("mine"))
        // The note stays while there is still a device that might offer it back.
        XCTAssertNotNil(merged.removedPlans[plan.id])
    }

    func testAPlanSavedAgainOutlivesItsOwnDeletion() {
        let deletedAt = clock.now
        let plan = MemoryPlan(
            id: "shared.plan",
            title: "Sent to me twice",
            passages: [PassageRef(.psalms, 23, 1, 6)],
            origin: .shared,
            createdAt: deletedAt.addingTimeInterval(3600)
        )
        let savedAgain = ProgressSnapshot(
            customPlans: [plan],
            updatedAt: deletedAt.addingTimeInterval(3600)
        )
        var deletedIt = snapshot(updatedAt: deletedAt)
        deletedIt.removedPlans[plan.id] = deletedAt

        let merged = ProgressMerge.merge(local: deletedIt, remote: savedAgain)

        XCTAssertEqual(merged.customPlans.map(\.id), [plan.id])
        XCTAssertNil(merged.removedPlans[plan.id])
    }

    func testPlansFromBothDevicesAreKept() {
        let now = clock.now
        let mine = MemoryPlan(id: "a", title: "A", passages: [PassageRef(.psalms, 23, 1, 6)], createdAt: now)
        let theirs = MemoryPlan(id: "b", title: "B", passages: [PassageRef(.psalms, 1, 1, 6)], createdAt: now)

        let merged = ProgressMerge.merge(
            local: ProgressSnapshot(customPlans: [mine], updatedAt: now),
            remote: ProgressSnapshot(customPlans: [theirs], updatedAt: now.addingTimeInterval(60))
        )

        XCTAssertEqual(Set(merged.customPlans.map(\.id)), ["a", "b"])
    }

    /// An edit to a plan both devices hold comes from the newer record.
    func testAnEditedPlanTakesTheNewerTitle() {
        let now = clock.now
        let before = MemoryPlan(id: "a", title: "A", passages: [PassageRef(.psalms, 23, 1, 6)], createdAt: now)
        var after = before
        after.title = "A, renamed"

        let merged = ProgressMerge.merge(
            local: ProgressSnapshot(customPlans: [before], updatedAt: now),
            remote: ProgressSnapshot(customPlans: [after], updatedAt: now.addingTimeInterval(60))
        )

        XCTAssertEqual(merged.customPlans.map(\.title), ["A, renamed"])
    }

    // MARK: - Stamping

    func testOpeningTheAppIsNotAChange() {
        var record = snapshot(updatedAt: clock.now)
        var opened = record
        opened.lastOpenedAt = clock.now.addingTimeInterval(86_400)
        opened.updatedAt = clock.now.addingTimeInterval(86_400)
        XCTAssertTrue(record.hasSameContent(as: opened))

        record.currentVerse = VerseRef(.psalms, 23, 4)
        XCTAssertFalse(record.hasSameContent(as: opened))
    }
}

/// The record as it travels: packed, versioned, and refused when it comes from
/// a build that knows more than this one.
final class CloudProgressPayloadTests: XCTestCase {
    private let clock = TestClock()

    func testARecordSurvivesTheRoundTrip() throws {
        var progress = ProgressSnapshot(updatedAt: clock.now)
        progress.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        progress.customPlans = [
            MemoryPlan(id: "mine", title: "Mine", passages: [PassageRef(.psalms, 23, 1, 6)], createdAt: clock.now)
        ]
        progress.activePlans = ["mine"]
        progress.reminderTime = ReminderTime(hour: 6, minute: 30)

        let record = try CloudProgressPayload.decode(CloudProgressPayload.encode(progress))

        XCTAssertEqual(record.snapshot, progress)
        XCTAssertEqual(record.schemaVersion, ProgressSnapshot.currentSchemaVersion)
        XCTAssertEqual(record.updatedAt, progress.updatedAt)
        XCTAssertFalse(record.isFromNewerSchema)
    }

    func testTheSameRecordPacksToTheSameBytes() throws {
        var progress = ProgressSnapshot(updatedAt: clock.now)
        progress.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        // What lets a push that would say nothing new be skipped.
        XCTAssertEqual(try CloudProgressPayload.encode(progress), try CloudProgressPayload.encode(progress))
    }

    /// The store takes 1 MB. Somebody who memorized the entire Bible has to
    /// fit, or the feature would quietly stop working for exactly the person
    /// who has most to lose. (References beyond the real Psalms are fine here:
    /// this is about the size of the record, not what it says.)
    func testTheWholeBibleMemorizedStillFits() throws {
        var progress = ProgressSnapshot(updatedAt: clock.now)
        let masteredAt = clock.now
        for chapter in 1...1_189 {
            let chapterRef = ChapterRef(.psalms, chapter)
            for verse in 1...26 {
                let ref = VerseRef(.psalms, chapter, verse)
                progress.verseStates[ref] = VerseState(
                    status: .mastered,
                    highestMaskLevelCleared: 4,
                    readCount: 3,
                    peekCount: 1,
                    masteredAt: masteredAt
                )
                progress.coveredUnits[.chapter(chapterRef), default: []].insert(ref)
            }
            progress.chapterStates[chapterRef] = ChapterState(
                fullRecitationConfirmed: true,
                cumulativeConfirmedThrough: 26,
                startedAt: masteredAt,
                completedAt: masteredAt
            )
        }

        let payload = try CloudProgressPayload.encode(progress)

        XCTAssertLessThanOrEqual(
            payload.count,
            CloudProgressPayload.sizeLimit,
            "30,914 memorized verses packed to \(payload.count) bytes"
        )
    }
}

/// Two devices, one record.
final class CloudProgressSyncTests: XCTestCase {
    private let clock = TestClock()
    private var store: InMemoryCloudProgressStore!

    override func setUp() {
        super.setUp()
        store = InMemoryCloudProgressStore()
    }

    private func sync() -> CloudProgressSync { CloudProgressSync(store: store, clock: clock) }

    func testANewDevicePicksUpEverythingTheOldOneLearned() throws {
        var onPhone = ProgressSnapshot(updatedAt: clock.now)
        onPhone.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        onPhone.activePlans = ["builtin.roman-road"]
        sync().push(onPhone)

        // A phone set up from a backup, or an app deleted and installed again:
        // nothing on disk, everything in iCloud.
        let adopted = try XCTUnwrap(sync().pull(into: ProgressSnapshot()))

        XCTAssertTrue(adopted.state(for: VerseRef(.psalms, 23, 1)).isMastered)
        XCTAssertEqual(adopted.activePlans, ["builtin.roman-road"])
    }

    func testTwoDevicesUsedApartKeepBothSetsOfWork() throws {
        var onPhone = ProgressSnapshot(updatedAt: clock.now)
        onPhone.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        sync().push(onPhone)

        var onIPad = ProgressSnapshot(updatedAt: clock.now.addingTimeInterval(60))
        onIPad.seedWorked(VerseRef(.psalms, 23, 2), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)

        let ipad = sync()
        let merged = try XCTUnwrap(ipad.pull(into: onIPad))
        XCTAssertTrue(merged.state(for: VerseRef(.psalms, 23, 1)).isMastered)
        XCTAssertTrue(merged.state(for: VerseRef(.psalms, 23, 2)).isMastered)

        // And it settles: once the union is up there, pulling it again has
        // nothing to say, so two devices cannot talk each other in circles.
        ipad.push(merged)
        XCTAssertNil(ipad.pull(into: merged))
    }

    func testNothingIsSentTwiceOver() throws {
        let progress = ProgressSnapshot(updatedAt: clock.now)
        let phone = sync()
        phone.push(progress)
        phone.push(progress)
        XCTAssertEqual(store.writes.count, 1)
    }

    func testARecordFromANewerVersionIsLeftAlone() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let record = try encoder.encode(ProgressSnapshot(updatedAt: clock.now))
        let fromTheFuture = CloudProgressEnvelope(
            schemaVersion: ProgressSnapshot.currentSchemaVersion + 1,
            updatedAt: clock.now,
            compression: .none,
            payload: record
        )
        try store.savePayload(encoder.encode(fromTheFuture))
        let writesBefore = store.writes.count

        var mine = ProgressSnapshot(updatedAt: clock.now)
        mine.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        let phone = sync()

        XCTAssertNil(phone.pull(into: mine))
        XCTAssertEqual(phone.status, .refusedNewerRecord)
        // Neither adopted nor overwritten: it may hold work this build cannot
        // even represent.
        phone.push(mine)
        XCTAssertEqual(store.writes.count, writesBefore)
    }

    func testAnUnreadableRecordChangesNothingHere() throws {
        try store.savePayload(Data("not a record at all".utf8))
        var mine = ProgressSnapshot(updatedAt: clock.now)
        mine.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)

        let phone = sync()
        XCTAssertNil(phone.pull(into: mine))
        // The device's own work is untouched, and it may still say its piece.
        phone.push(mine)
        XCTAssertNotNil(try store.loadPayload())
    }

    func testErasingProgressTakesTheCloudCopyWithIt() throws {
        let phone = sync()
        phone.push(ProgressSnapshot(updatedAt: clock.now))
        XCTAssertNotNil(try store.loadPayload())

        phone.removeStoredCopy()

        XCTAssertNil(try store.loadPayload())
    }

    func testADifferentAccountStopsTheDeviceSyncing() throws {
        let phone = sync()
        phone.push(ProgressSnapshot(updatedAt: clock.now))
        let writesBefore = store.writes.count

        XCTAssertFalse(phone.handle(.accountChanged))
        XCTAssertEqual(phone.status, .accountChanged)

        var mine = ProgressSnapshot(updatedAt: clock.now.addingTimeInterval(60))
        mine.seedWorked(VerseRef(.psalms, 23, 1), by: .chapter(ChapterRef(.psalms, 23)), at: clock.now)
        phone.push(mine)
        XCTAssertNil(phone.pull(into: mine))
        // One account's work is never filed under another's.
        XCTAssertEqual(store.writes.count, writesBefore)
    }

    func testAnEmptyCloudIsNotAFailure() {
        let phone = sync()
        XCTAssertNil(phone.pull(into: ProgressSnapshot(updatedAt: clock.now)))
        XCTAssertEqual(phone.status, .idle)
    }
}

final class CloudSyncPreferenceTests: XCTestCase {
    func testItIsOnUntilSomebodySaysOtherwise() throws {
        let suite = "cloud-sync-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = CloudSyncPreference(defaults: defaults)

        XCTAssertTrue(preference.isEnabled)

        preference.isEnabled = false
        XCTAssertFalse(CloudSyncPreference(defaults: defaults).isEnabled)

        preference.isEnabled = true
        XCTAssertTrue(CloudSyncPreference(defaults: defaults).isEnabled)
    }
}
