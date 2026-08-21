import XCTest

@testable import BibleCore

/// §7.2: the runtime masking rule, and the tokenizer that feeds it.
final class MaskingTests: XCTestCase {
    private func verse(_ text: String, chapter: Int = 1, verse: Int = 1) -> Verse {
        Verse(
            ref: VerseRef(Fixture.testBook, chapter, verse),
            lines: [Line(indent: 1, text: text)],
            startsParagraph: false,
            bookOrder: 1
        )
    }

    // MARK: - Tokenizer

    func testSplitsPunctuationFromWords() {
        let tokens = verse("The LORD is my shepherd; I shall not want.").tokens
        XCTAssertTrue(tokens.contains { $0.kind == .punctuation && $0.text == ";" })
        XCTAssertTrue(tokens.contains { $0.kind == .word && $0.text == "shepherd" })
    }

    func testKeepsInternalApostrophesAndHyphens() {
        let words = verse("the LORD's loving-kindness").tokens.filter { $0.kind == .word }
        XCTAssertEqual(words.map(\.text), ["the", "LORD's", "loving-kindness"])
    }

    func testGroupsAdjacentPunctuation() {
        let tokens = verse("like pottery.”").tokens
        XCTAssertEqual(tokens.last?.kind, .punctuation)
        XCTAssertEqual(tokens.last?.text, ".”")
    }

    func testSelahIsItsOwnKindAndNeverMaskable() throws {
        let tokens = verse("deliver him. Selah").tokens
        let selah = try XCTUnwrap(tokens.first { $0.kind == .selah })
        XCTAssertEqual(selah.text, "Selah")
        XCTAssertNil(selah.maskIndex)
    }

    func testTokensReconstructTheText() {
        let text = "“Let us break Their chains, and cast away Their cords.”"
        XCTAssertEqual(Masking.plainText(verse(text), level: .none), text)
    }

    func testLineBreaksSeparateLines() {
        let poetic = Verse(
            ref: VerseRef(Fixture.testBook, 1, 1),
            lines: [Line(indent: 1, text: "The LORD is my shepherd;"), Line(indent: 2, text: "I shall not want.")],
            startsParagraph: false,
            bookOrder: 1
        )
        XCTAssertEqual(poetic.tokens.filter { $0.kind == .lineBreak }.count, 1)
        XCTAssertEqual(poetic.tokens.first { $0.kind == .lineBreak }?.indent, 2)
        XCTAssertEqual(Masking.plainText(poetic, level: .none), "The LORD is my shepherd;\nI shall not want.")
    }

    func testATrailingDashStaysPunctuation() {
        let words = verse("His clouds advanced— hailstones").tokens.filter { $0.kind == .word }
        XCTAssertEqual(words.map(\.text), ["His", "clouds", "advanced", "hailstones"])
    }

    // MARK: - Mask levels

    func testIntermediateLevelsRoundUp() {
        XCTAssertEqual(Masking.maskedWordCount(wordCount: 6, level: .quarter), 2)
        XCTAssertEqual(Masking.maskedWordCount(wordCount: 6, level: .half), 3)
        XCTAssertEqual(Masking.maskedWordCount(wordCount: 6, level: .threeQuarters), 5)
        XCTAssertEqual(Masking.maskedWordCount(wordCount: 1, level: .quarter), 1)
        XCTAssertEqual(Masking.maskedWordCount(wordCount: 0, level: .full), 0)
    }

    func testLevelZeroAndFour() {
        let v = verse("one two three four five six seven eight")
        XCTAssertEqual(Masking.mask(v, level: .none).filter { $0 }.count, 0)
        XCTAssertEqual(Masking.mask(v, level: .full).filter { $0 }.count, v.wordCount)
    }

    func testMaskedSetGrowsMonotonically() {
        let v = verse("a b c d e f g h i j k l m")
        var previous: Set<Int> = []
        for level in MaskLevel.allCases {
            let masked = Set(
                v.tokens.enumerated()
                    .filter { Masking.isMasked($0.element, level: level, wordCount: v.wordCount) }
                    .map(\.offset)
            )
            XCTAssertTrue(previous.isSubset(of: masked), "level \(level) revealed a word")
            previous = masked
        }
    }

    // MARK: - Mask ordering

    func testOrderIsAPermutation() {
        for n in [1, 2, 5, 17, 60] {
            XCTAssertEqual(MaskOrder.order(count: n, seed: 12345).sorted(), Array(0..<n))
        }
    }

    func testOrderIsDeterministic() {
        let seed = MaskOrder.seed(book: 19, chapter: 119, verse: 42)
        XCTAssertEqual(MaskOrder.order(count: 20, seed: seed), MaskOrder.order(count: 20, seed: seed))
    }

    func testSeedsDifferAcrossBooksChaptersAndVerses() {
        let base = MaskOrder.seed(book: 19, chapter: 23, verse: 1)
        XCTAssertNotEqual(base, MaskOrder.seed(book: 20, chapter: 23, verse: 1))
        XCTAssertNotEqual(base, MaskOrder.seed(book: 19, chapter: 24, verse: 1))
        XCTAssertNotEqual(base, MaskOrder.seed(book: 19, chapter: 23, verse: 2))
    }

    /// §7.2 #3: at 25% the hidden words must be spread across the verse.
    func testLevelOneMasksAreDistributedNotClustered() {
        for n in 8...60 {
            let order = MaskOrder.order(count: n, seed: MaskOrder.seed(book: 1, chapter: 1, verse: n))
            let k = (n + 3) / 4
            let chosen = order.prefix(k).sorted()
            XCTAssertTrue(
                chosen.first! < n / 2 && chosen.last! >= n / 2,
                "n=\(n): level-1 masks clustered in one half"
            )
        }
    }

    // MARK: - VoiceOver (§12)

    func testMaskedWordsAnnounceAsBlank() {
        let v = verse("The LORD is my shepherd")
        XCTAssertEqual(Masking.spokenText(v, level: .full), "Verse 1. blank blank blank blank blank")
        XCTAssertEqual(Masking.spokenText(v, level: .none), "Verse 1. The LORD is my shepherd")
    }
}

/// Masking a whole block at once, for Review mode.
final class BlockMaskingTests: XCTestCase {
    private func verses(_ count: Int) -> [Verse] {
        (1...count).map { Fixture.verse($0, wordCount: 8) }
    }

    func testLevelZeroHidesNothingAndLevelFourHidesEverything() {
        let block = verses(4)
        XCTAssertEqual(BlockMasking.maskedWordCount(block, level: .none), 0)
        XCTAssertEqual(BlockMasking.maskedWordCount(block, level: .full), BlockMasking.wordCount(block))
    }

    func testEveryVerseInTheBlockIsMaskedNotJustTheFirst() {
        for verse in verses(4) {
            XCTAssertGreaterThan(
                Masking.mask(verse, level: .half).filter { $0 }.count, 0,
                "verse \(verse.number) was left fully visible"
            )
        }
    }

    func testTheSameWordsHideEveryTime() {
        let block = verses(3)
        XCTAssertEqual(
            BlockMasking.plainText(block, level: .half),
            BlockMasking.plainText(block, level: .half)
        )
    }
}
