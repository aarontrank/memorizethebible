import Foundation
import XCTest

@testable import BibleCore

final class PlanSharingTests: XCTestCase {
    private func plan(
        id: String = "plan-1",
        title: String = "Verses for a hard week",
        summary: String = "Five to hold on to.",
        sections: [MemoryPlan.Section]? = nil
    ) -> MemoryPlan {
        MemoryPlan(
            id: id,
            title: title,
            summary: summary,
            sections: sections
                ?? [
                    MemoryPlan.Section(
                        id: "s1",
                        title: "Promises",
                        passages: [
                            PassageRef(BookID("ROM"), 8, 28),
                            PassageRef(BookID("PSA"), 23, 1, 6),
                        ]
                    )
                ]
        )
    }

    // MARK: - Round trip

    func testAPlanSurvivesTheRoundTrip() throws {
        let original = plan()
        let restored = try PlanSharing.plan(from: PlanSharing.link(for: original))
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.summary, original.summary)
        XCTAssertEqual(restored.passages, original.passages)
        XCTAssertEqual(restored.sections.map(\.title), original.sections.map(\.title))
    }

    func testTheSenderIsIdentityIsKeptSoResharingUpdatesRatherThanDuplicates() throws {
        let original = plan(id: "abc-123")
        let restored = try PlanSharing.plan(from: PlanSharing.link(for: original))
        XCTAssertEqual(restored.id, "abc-123")
    }

    func testAReceivedPlanIsMarkedShared() throws {
        let restored = try PlanSharing.plan(from: PlanSharing.link(for: plan()))
        XCTAssertEqual(restored.origin, .shared)
        XCTAssertFalse(restored.isBuiltIn)
    }

    func testASharedPlanCanBeSharedOnwardUnchanged() throws {
        let once = try PlanSharing.plan(from: PlanSharing.link(for: plan()))
        let twice = try PlanSharing.plan(from: PlanSharing.link(for: once))
        XCTAssertEqual(twice.passages, once.passages)
        XCTAssertEqual(twice.id, once.id)
    }

    func testMultipleSectionsKeepTheirOrderAndTitles() throws {
        let original = plan(sections: [
            MemoryPlan.Section(id: "a", title: "First", passages: [PassageRef(BookID("JHN"), 3, 16)]),
            MemoryPlan.Section(id: "b", title: "Second", passages: [PassageRef(BookID("JHN"), 1, 1, 3)]),
        ])
        let restored = try PlanSharing.plan(from: PlanSharing.link(for: original))
        XCTAssertEqual(restored.sections.map(\.title), ["First", "Second"])
        XCTAssertEqual(restored.sections[1].passages, [PassageRef(BookID("JHN"), 1, 1, 3)])
    }

    func testASuperscriptionPassageSurvives() throws {
        // Verse 0 is a psalm's heading, and 0 is a legitimate verse number.
        let original = plan(sections: [
            MemoryPlan.Section(id: "a", title: "T", passages: [PassageRef(BookID("PSA"), 3, 0, 8)])
        ])
        let restored = try PlanSharing.plan(from: PlanSharing.link(for: original))
        XCTAssertEqual(restored.passages, [PassageRef(BookID("PSA"), 3, 0, 8)])
    }

    // MARK: - The link itself

    func testLinksAreWrittenAsUniversalLinks() throws {
        let url = try PlanSharing.link(for: plan())
        XCTAssertTrue(PlanSharing.isPlanLink(url))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "aarontrank.com")
        XCTAssertEqual(url.path, "/projects/memorize-the-bible/plan")
    }

    /// The site claims `plan*`, and redirects the bare path to the slashed one.
    func testTheTrailingSlashFormIsOursToo() throws {
        let payload = #"{"v":1,"i":"x","t":"T","s":"","x":[{"t":"S","p":["JHN.3.16"]}]}"#
        let encoded = PlanSharing.base64URL(Data(payload.utf8))
        let url = URL(string: "https://aarontrank.com/projects/memorize-the-bible/plan/?d=\(encoded)")!
        XCTAssertTrue(PlanSharing.isPlanLink(url))
        XCTAssertEqual(try PlanSharing.plan(from: url).title, "T")
    }

    /// Links written before the move are out in people's messages already.
    func testTheOldCustomSchemeStillOpens() throws {
        let payload = #"{"v":1,"i":"x","t":"Sent last year","s":"","x":[{"t":"S","p":["ROM.8.28"]}]}"#
        let encoded = PlanSharing.base64URL(Data(payload.utf8))
        let url = URL(string: "memorizethebible://plan?d=\(encoded)")!
        XCTAssertTrue(PlanSharing.isPlanLink(url))
        XCTAssertEqual(try PlanSharing.plan(from: url).title, "Sent last year")
    }

    func testAnotherPageOnTheSameSiteIsNotAPlanLink() {
        for address in [
            "https://aarontrank.com/projects/memorize-the-bible/",
            "https://aarontrank.com/projects/memorize-the-bible/terms/",
            "https://aarontrank.com/plan",
            "https://example.com/projects/memorize-the-bible/plan",
            "http://aarontrank.com/projects/memorize-the-bible/plan",
        ] {
            XCTAssertFalse(PlanSharing.isPlanLink(URL(string: address)!), address)
        }
    }

    func testTheLinkNeedsNoPercentEscaping() throws {
        // base64url keeps the payload to characters a query can hold as-is, so
        // nothing is mangled by an app that re-encodes the link in transit.
        let url = try PlanSharing.link(for: plan(title: "A/B+C ünïcode"))
        XCTAssertFalse(url.absoluteString.contains("%"))
    }

    func testTheSamePlanAlwaysProducesTheSameLink() throws {
        let subject = plan()
        XCTAssertEqual(
            try PlanSharing.link(for: subject).absoluteString,
            try PlanSharing.link(for: subject).absoluteString
        )
    }

    func testALinkForAnOrdinaryPlanStaysShortEnoughToSend() throws {
        let url = try PlanSharing.link(for: BuiltInPlans.sermonOnTheMount)
        XCTAssertLessThan(url.absoluteString.count, 900, url.absoluteString)
    }

    // MARK: - Refusals

    func testSomeOtherLinkIsNotAPlan() {
        let url = URL(string: "https://example.com/somewhere?d=abc")!
        XCTAssertFalse(PlanSharing.isPlanLink(url))
        XCTAssertThrowsError(try PlanSharing.plan(from: url)) {
            XCTAssertEqual($0 as? PlanSharingError, .notAPlanLink)
        }
    }

    func testATruncatedLinkIsRefusedRatherThanHalfRead() throws {
        let full = try PlanSharing.link(for: plan()).absoluteString
        let cut = URL(string: String(full.prefix(full.count - 12)))!
        XCTAssertThrowsError(try PlanSharing.plan(from: cut)) {
            XCTAssertEqual($0 as? PlanSharingError, .malformed)
        }
    }

    func testALinkWithNoPayloadIsRefused() {
        let url = URL(string: "https://aarontrank.com/projects/memorize-the-bible/plan")!
        XCTAssertThrowsError(try PlanSharing.plan(from: url)) {
            XCTAssertEqual($0 as? PlanSharingError, .malformed)
        }
    }

    func testAFutureFormatIsRefusedRatherThanGuessedAt() throws {
        let payload = #"{"v":99,"i":"x","t":"T","s":"","x":[{"t":"S","p":["ROM.8.28"]}]}"#
        let url = link(payload: payload)
        XCTAssertThrowsError(try PlanSharing.plan(from: url)) {
            XCTAssertEqual($0 as? PlanSharingError, .newerVersion)
        }
    }

    func testAPlanNamingNoVersesIsRefused() {
        let url = link(payload: #"{"v":1,"i":"x","t":"T","s":"","x":[]}"#)
        XCTAssertThrowsError(try PlanSharing.plan(from: url)) {
            XCTAssertEqual($0 as? PlanSharingError, .noVerses)
        }
    }

    func testUnreadablePassagesAreDroppedAndTheRestSurvives() throws {
        let payload =
            #"{"v":1,"i":"x","t":"T","s":"","x":[{"t":"S","p":["ROM.8.28","nonsense","PSA.0.1","ROM.3.-4","JHN.3.16"]}]}"#
        let restored = try PlanSharing.plan(from: link(payload: payload))
        XCTAssertEqual(restored.passages, [PassageRef(BookID("ROM"), 8, 28), PassageRef(BookID("JHN"), 3, 16)])
    }

    func testASectionLeftWithNoReadablePassagesIsDropped() throws {
        let payload =
            #"{"v":1,"i":"x","t":"T","s":"","x":[{"t":"Gone","p":["junk"]},{"t":"Kept","p":["JHN.3.16"]}]}"#
        let restored = try PlanSharing.plan(from: link(payload: payload))
        XCTAssertEqual(restored.sections.map(\.title), ["Kept"])
    }

    func testAnEmptyTitleGetsOneRatherThanShowingAsBlank() throws {
        let payload = #"{"v":1,"i":"x","t":"   ","s":"","x":[{"t":"S","p":["JHN.3.16"]}]}"#
        XCTAssertEqual(try PlanSharing.plan(from: link(payload: payload)).title, "Shared plan")
    }

    func testAnAbsurdlyLongTitleIsClampedRatherThanRefused() throws {
        let long = String(repeating: "x", count: 5_000)
        let payload = #"{"v":1,"i":"x","t":"\#(long)","s":"","x":[{"t":"S","p":["JHN.3.16"]}]}"#
        let restored = try PlanSharing.plan(from: link(payload: payload))
        XCTAssertEqual(restored.title.count, PlanSharing.maxTitleLength)
    }

    func testAnAbsurdNumberOfPassagesIsCappedRatherThanRefused() throws {
        let passages = (1...2_000).map { "\"JHN.3.\($0)\"" }.joined(separator: ",")
        let payload = #"{"v":1,"i":"x","t":"T","s":"","x":[{"t":"S","p":[\#(passages)]}]}"#
        let restored = try PlanSharing.plan(from: link(payload: payload))
        XCTAssertEqual(restored.passages.count, PlanSharing.maxPassagesPerSection)
    }

    // MARK: - Passage text

    func testPassageTextIsCompact() {
        XCTAssertEqual(PlanSharing.encode(PassageRef(BookID("ROM"), 3, 23)), "ROM.3.23")
        XCTAssertEqual(PlanSharing.encode(PassageRef(BookID("ROM"), 10, 9, 10)), "ROM.10.9-10")
    }

    func testPassageTextRoundTrips() {
        for passage in [
            PassageRef(BookID("ROM"), 3, 23),
            PassageRef(BookID("PSA"), 119, 1, 176),
            PassageRef(BookID("PSA"), 3, 0),
        ] {
            XCTAssertEqual(PlanSharing.decodePassage(PlanSharing.encode(passage)), passage)
        }
    }

    func testMalformedPassageTextIsRejected() {
        for text in ["", "ROM", "ROM.3", "ROM.3.4.5", ".3.4", "ROM.x.4", "ROM.3.x", "ROM.0.1", "ROM.3.9-4"] {
            XCTAssertNil(PlanSharing.decodePassage(text), text)
        }
    }

    // MARK: - Storage compatibility

    func testAPlanStoredBeforeSharingExistedStillDecodes() throws {
        // The shape written by the version before `origin` was added.
        let json = """
            {"id":"old","title":"Old plan","summary":"","isBuiltIn":false,
             "sections":[{"id":"s","title":"S","passages":[{"book":"ROM","chapter":8,"firstVerse":28,"lastVerse":28}]}]}
            """
        let decoded = try JSONDecoder().decode(MemoryPlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.origin, .own)
        XCTAssertEqual(decoded.title, "Old plan")
    }

    private func link(payload: String) -> URL {
        let encoded = PlanSharing.base64URL(Data(payload.utf8))
        return URL(string: "https://aarontrank.com/projects/memorize-the-bible/plan?d=\(encoded)")!
    }
}
