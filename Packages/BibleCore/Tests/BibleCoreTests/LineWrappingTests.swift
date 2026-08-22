import XCTest

@testable import BibleCore

/// Punctuation must never be left to start a line on its own.
final class LineWrappingTests: XCTestCase {
    private func verse(_ text: String, lines: [String]? = nil) -> Verse {
        Verse(
            ref: VerseRef(Fixture.testBook, 1, 1),
            lines: (lines ?? [text]).map { Line(indent: 1, text: $0) },
            startsParagraph: false,
            bookOrder: 1
        )
    }

    /// The groups as text, which is the readable way to assert on this.
    private func grouped(_ verse: Verse) -> [String] {
        LineWrapping.groups(for: verse.tokens).map { group in
            group.map { verse.tokens[$0].kind == .lineBreak ? "⏎" : verse.tokens[$0].text }.joined()
        }
    }

    func testACommaStaysWithItsWord() {
        XCTAssertEqual(
            grouped(verse("Blessed is the man who does not walk, or set foot")),
            ["Blessed", "is", "the", "man", "who", "does", "not", "walk,", "or", "set", "foot"]
        )
    }

    func testAFullStopStaysWithItsWord() {
        XCTAssertEqual(grouped(verse("I shall not want.")), ["I", "shall", "not", "want."])
    }

    func testAnOpeningQuoteStaysWithTheWordItOpens() {
        XCTAssertEqual(
            grouped(verse("say, “God will not deliver him.”")),
            ["say,", "“God", "will", "not", "deliver", "him.”"]
        )
    }

    func testAClosingRunOfPunctuationStaysPut() {
        XCTAssertEqual(grouped(verse("like pottery.”")), ["like", "pottery.”"])
    }

    /// A dash with a space on either side has nothing holding it, so it joins
    /// the word before rather than being left to open a line.
    func testFloatingPunctuationJoinsTheWordBefore() {
        XCTAssertEqual(
            grouped(verse("His clouds advanced — hailstones and coals")),
            // The helper joins a group's texts without spaces, so the merged
            // dash shows up butted against the word it now travels with.
            ["His", "clouds", "advanced—", "hailstones", "and", "coals"]
        )
    }

    func testALineBreakIsItsOwnGroup() {
        let poetic = verse("", lines: ["The LORD is my shepherd;", "I shall not want."])
        XCTAssertEqual(
            grouped(poetic),
            ["The", "LORD", "is", "my", "shepherd;", "⏎", "I", "shall", "not", "want."]
        )
    }

    func testPunctuationOpeningALineIsLeftAlone() {
        // Nothing precedes it on the line, so there is nothing to join.
        let poetic = verse("", lines: ["hear me", "“ Lord"])
        let groups = grouped(poetic)
        XCTAssertTrue(groups.contains("“"), "\(groups)")
    }

    func testEmptyInput() {
        XCTAssertTrue(LineWrapping.groups(for: []).isEmpty)
    }

    func testEveryTokenLandsInExactlyOneGroup() {
        let v = verse("Rejoice at all times, and pray — without ceasing.")
        let flattened = LineWrapping.groups(for: v.tokens).flatMap { $0 }.sorted()
        XCTAssertEqual(flattened, Array(v.tokens.indices))
    }
}

/// The rule, checked against the whole Bible.
final class CorpusLineWrappingTests: XCTestCase {
    private static var store: ContentStore!

    override class func setUp() {
        super.setUp()
        store = try? Fixture.realContentStore()
    }

    /// No group may be punctuation alone unless it opens a line — which is the
    /// only place there is nothing before it to attach to.
    func testNoPunctuationIsLeftDanglingAnywhereInTheBible() throws {
        guard let store = Self.store else { throw XCTSkip("bundled content not built") }
        var offenders: [String] = []

        for book in store.books {
            for summary in book.chapters {
                let chapter = try store.chapter(ChapterRef(book.id, summary.number))
                for verse in chapter.verses {
                    let tokens = verse.tokens
                    for group in LineWrapping.groups(for: tokens) {
                        guard group.allSatisfy({ tokens[$0].kind == .punctuation }) else { continue }
                        let first = group[0]
                        // Acceptable only at the very start of a rendered line.
                        let opensLine = first == 0 || tokens[first - 1].kind == .lineBreak
                        if !opensLine {
                            offenders.append("\(verse.ref) \(group.map { tokens[$0].text }.joined())")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(offenders.count, 0, "dangling punctuation: \(offenders.prefix(10))")
    }
}
