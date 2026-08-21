import XCTest

@testable import BibleCore

/// The whole-Bible corpus, checked against the runtime tokenizer.
///
/// Tokenisation moved from the Python pipeline into Swift when the app grew
/// past Psalms. These are the tests that make that move safe: they assert the
/// runtime reproduces the text exactly, verse for verse, across all 31,086.
final class CorpusTests: XCTestCase {
    private static var store: ContentStore!

    override class func setUp() {
        super.setUp()
        store = try? Fixture.realContentStore()
    }

    private var store: ContentStore {
        get throws {
            guard let store = Self.store else { throw XCTSkip("bundled content not built") }
            return store
        }
    }

    func testManifestFigures() throws {
        let store = try store
        XCTAssertEqual(store.translationId, "bsb")
        XCTAssertEqual(store.translationName, "Berean Standard Bible")
        XCTAssertEqual(store.bookCount, 66)
        XCTAssertEqual(store.manifest.chapterCount, 1189)
        XCTAssertEqual(store.verseCount, 31086)
        XCTAssertFalse(store.attributionNotice.isEmpty, "§4: required on the About screen")
    }

    func testBooksAreInCanonicalOrderAndSplitByTestament() throws {
        let store = try store
        XCTAssertEqual(store.books.map(\.order), Array(1...66))
        XCTAssertEqual(store.manifest.books(in: .old).count, 39)
        XCTAssertEqual(store.manifest.books(in: .new).count, 27)
        XCTAssertEqual(store.books.first?.name, "Genesis")
        XCTAssertEqual(store.books.last?.name, "Revelation")
    }

    func testWellKnownShapes() throws {
        let store = try store
        XCTAssertEqual(store.book(.psalms)?.chapterCount, 150)
        XCTAssertEqual(store.book(BookID("GEN"))?.chapterCount, 50)
        XCTAssertEqual(store.book(BookID("REV"))?.chapterCount, 22)
        XCTAssertEqual(try store.chapter(ChapterRef(.psalms, 119)).verseCount, 176)
        XCTAssertEqual(try store.chapter(ChapterRef(.psalms, 117)).verseCount, 2)
        XCTAssertEqual(try store.chapter(ChapterRef(BookID("JHN"), 11)).verse(35)?.text, "Jesus wept.")
    }

    /// The BSB prints sixteen New Testament verses empty; they are not shipped,
    /// so those chapters have deliberate gaps in their numbering.
    func testOmittedVersesLeaveGapsRatherThanEmptyVerses() throws {
        let store = try store
        let matthew17 = try store.chapter(ChapterRef(BookID("MAT"), 17))
        XCTAssertNil(matthew17.verse(21), "Matthew 17:21 is not in the BSB")
        XCTAssertNotNil(matthew17.verse(20))
        XCTAssertNotNil(matthew17.verse(22))
        XCTAssertEqual(matthew17.verseCount, 26)
    }

    func testEveryVerseHasTextAndWords() throws {
        let store = try store
        for book in try store.books {
            for summary in book.chapters {
                let chapter = try store.chapter(ChapterRef(book.id, summary.number))
                for verse in chapter.verses {
                    XCTAssertFalse(verse.text.isEmpty, "\(verse.ref) is empty")
                    XCTAssertGreaterThan(verse.wordCount, 0, "\(verse.ref) has no maskable words")
                }
            }
        }
    }

    /// The renderer draws tokens, so tokens must reconstruct the verse exactly.
    func testTokensReconstructEveryVerse() throws {
        let store = try store
        for book in try store.books {
            for summary in book.chapters {
                let ref = ChapterRef(book.id, summary.number)
                let chapter = try store.chapter(ref)
                for verse in chapter.units {
                    let rebuilt = Masking.plainText(verse, level: .none)
                        .replacingOccurrences(of: "\n", with: " ")
                    XCTAssertEqual(rebuilt, verse.text, "\(verse.ref) does not round-trip")
                }
            }
        }
    }

    func testMaskIndicesAreACompletePermutationEverywhere() throws {
        let store = try store
        for book in try store.books {
            for summary in book.chapters {
                let chapter = try store.chapter(ChapterRef(book.id, summary.number))
                for verse in chapter.units {
                    let indices = verse.tokens.compactMap(\.maskIndex).sorted()
                    XCTAssertEqual(
                        indices, Array(0..<verse.wordCount),
                        "\(verse.ref) mask indices are not 0..<wordCount"
                    )
                }
            }
        }
    }

    func testManifestAgreesWithLoadedChapters() throws {
        let store = try store
        for book in try store.books {
            for summary in book.chapters {
                let chapter = try store.chapter(ChapterRef(book.id, summary.number))
                XCTAssertEqual(summary.verseCount, chapter.verseCount, "\(book.id) \(summary.number)")
                XCTAssertEqual(summary.hasSuperscription, chapter.superscription != nil)
                XCTAssertEqual(summary.stanzas, chapter.stanzas)
                XCTAssertEqual(summary.firstVerse, chapter.verses.first?.number)
            }
        }
    }

    // MARK: - Psalms specifics, carried over from when this shipped Psalms alone

    func testSuperscriptionsAreSeparateFromVerseOne() throws {
        let store = try store
        let psalm3 = try store.chapter(ChapterRef(.psalms, 3))
        XCTAssertEqual(
            psalm3.superscription?.text, "A Psalm of David, when he fled from his son Absalom."
        )
        XCTAssertTrue(psalm3.verses[0].text.hasPrefix("O LORD, how my foes have increased!"))
        XCTAssertNil(try store.chapter(ChapterRef(.psalms, 1)).superscription)
    }

    func testOnlyPsalmsCarrySuperscriptions() throws {
        let store = try store
        var count = 0
        for book in try store.books {
            for summary in book.chapters where summary.hasSuperscription {
                count += 1
                XCTAssertEqual(book.id, .psalms, "\(book.id) \(summary.number)")
            }
        }
        XCTAssertEqual(count, 116)
    }

    func testPsalm119KeepsItsAcrosticStanzas() throws {
        let stanzas = try XCTUnwrap(try store.chapter(ChapterRef(.psalms, 119)).stanzas)
        XCTAssertEqual(stanzas.count, 22)
        XCTAssertEqual(stanzas.first?.title, "Aleph")
        XCTAssertTrue(stanzas.allSatisfy { $0.endVerse - $0.startVerse == 7 })
    }

    func testLongChaptersOutsidePsalmsAreStanzaScoped() throws {
        let store = try store
        // Numbers 7 is the longest chapter outside Psalms.
        let numbers7 = try store.chapter(ChapterRef(BookID("NUM"), 7))
        XCTAssertGreaterThan(numbers7.verseCount, 40)
        XCTAssertNotNil(numbers7.stanzas, "a long chapter needs blocks to be memorizable")
    }

    func testSelahIsNeverMaskable() throws {
        let store = try store
        var selahs = 0
        for summary in try XCTUnwrap(store.book(.psalms)).chapters {
            let chapter = try store.chapter(ChapterRef(.psalms, summary.number))
            for verse in chapter.verses {
                for token in verse.tokens where token.kind == .selah {
                    selahs += 1
                    XCTAssertNil(token.maskIndex, "§7.2 #5: Selah is never masked")
                }
            }
        }
        XCTAssertGreaterThan(selahs, 60)
    }

    func testLoadingOneChapterDoesNotRequireTheWholeBible() throws {
        let store = try store
        let chapter = try store.chapter(ChapterRef(BookID("ROM"), 8))
        XCTAssertEqual(chapter.verseCount, 39)
        XCTAssertThrowsError(try store.chapter(ChapterRef(BookID("XYZ"), 1)))
        XCTAssertThrowsError(try store.chapter(ChapterRef(BookID("ROM"), 99)))
    }
}

extension Chapter {
    /// Verses plus the superscription, for tests that check every unit.
    var units: [Verse] {
        if let superscription { return [superscription] + verses }
        return verses
    }
}
