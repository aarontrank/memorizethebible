import Foundation
import XCTest

@testable import BibleCore

/// Builders for synthetic content, so engine tests do not depend on the real
/// corpus (there is a separate suite for that).
enum Fixture {
    static let testBook = BookID("TST")

    static func verse(_ number: Int, wordCount: Int = 6, book: BookID = testBook, chapter: Int = 1) -> Verse {
        let text = (0..<wordCount).map { "w\(number)_\($0)" }.joined(separator: " ") + "."
        return Verse(
            ref: VerseRef(book, chapter, number),
            lines: [Line(indent: 1, text: text)],
            startsParagraph: false,
            bookOrder: 1
        )
    }

    static func chapter(
        _ number: Int = 1,
        verseCount: Int,
        book: BookID = testBook,
        hasSuperscription: Bool = false,
        stanzaSize: Int? = nil
    ) -> Chapter {
        let verses = (1...verseCount).map { verse($0, book: book, chapter: number) }
        var stanzas: [Stanza]?
        if let stanzaSize {
            stanzas = stride(from: 1, through: verseCount, by: stanzaSize).enumerated().map { index, start in
                Stanza(
                    index: index,
                    title: "S\(index)",
                    startVerse: start,
                    endVerse: min(start + stanzaSize - 1, verseCount)
                )
            }
        }
        let superscription = hasSuperscription
            ? Verse(
                ref: VerseRef(book, number, 0),
                lines: [Line(indent: 1, text: "A Psalm of David.")],
                startsParagraph: false,
                bookOrder: 1
            )
            : nil
        return Chapter(
            ref: ChapterRef(book, number),
            superscription: superscription,
            verses: verses,
            stanzas: stanzas
        )
    }

    /// A manifest describing synthetic chapters, so `ContentStore` and
    /// `ProgressReport` can be exercised without files.
    static func store(_ chapters: [Chapter], bookName: String = "Test Book") throws -> ContentStore {
        let byBook = Dictionary(grouping: chapters, by: \.book)
        let books = byBook.keys.sorted { $0.rawValue < $1.rawValue }.enumerated().map { index, id -> BookSummary in
            let bookChapters = byBook[id]!.sorted { $0.number < $1.number }
            let summaries = bookChapters.map { chapter in
                ChapterSummary(
                    number: chapter.number,
                    verseCount: chapter.verses.count,
                    firstVerse: chapter.verses.first?.number ?? 1,
                    hasSuperscription: chapter.superscription != nil,
                    firstLine: chapter.verses.first?.text ?? "",
                    stanzas: chapter.stanzas
                )
            }
            return BookSummary(
                id: id,
                name: id == .psalms ? "Psalms" : bookName,
                order: index + 1,
                testament: .old,
                chapters: summaries
            )
        }
        let manifest = ContentManifest(
            schemaVersion: 2,
            translationId: "test",
            name: "Test Translation",
            attributionNotice: "Test.",
            longChapterVerseThreshold: SessionRules.longChapterVerseThreshold,
            bookCount: books.count,
            chapterCount: chapters.count,
            verseCount: chapters.reduce(0) { $0 + $1.verses.count },
            books: books
        )
        return InMemoryContentStore(manifest: manifest, chapters: chapters)
    }

    /// The real bundled corpus, for the content-integrity suite.
    static func realContentStore() throws -> ContentStore {
        try ContentStore(source: DirectoryContentSource(directory: contentDirectory))
    }

    static var contentDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // BibleCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // BibleCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("App/MemorizeBible/Resources/Content")
    }
}

/// A `ContentStore` backed by chapters held in memory rather than JSON.
final class InMemoryContentStore: ContentStore {
    private let prebuilt: [ChapterRef: Chapter]

    init(manifest: ContentManifest, chapters: [Chapter]) {
        prebuilt = Dictionary(uniqueKeysWithValues: chapters.map { ($0.ref, $0) })
        super.init(manifest: manifest)
    }

    override func chapter(_ ref: ChapterRef) throws -> Chapter {
        guard let chapter = prebuilt[ref] else { throw ContentError("no chapter \(ref.storageKey)") }
        return chapter
    }
}

extension ProgressSnapshot {
    /// Seeds a verse as work already done inside `target`: mastered, read, and
    /// covered. Without the coverage the engine would rightly stop and ask
    /// whether to keep it, which is a different scenario.
    mutating func seedWorked(_ ref: VerseRef, by target: MemoryTargetID, at date: Date) {
        update(ref) { state in
            state.status = .mastered
            state.masteredAt = date
            state.readCount = SessionRules.requiredReads
            state.highestMaskLevelCleared = 4
        }
        markCovered(ref, by: target)
        if case let .chapter(chapterRef) = target, state(for: chapterRef).startedAt == nil {
            update(chapterRef) { $0.startedAt = date }
        }
    }
}

extension SessionEngine {
    /// Drive a verse from untouched to mastered: three reads, then the ladder
    /// to a clean level-4 pass.
    func takeVerseToMastered(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<SessionRules.requiredReads {
            guard case .read = step else { break }
            confirmCurrentStep()
        }
        var guardCount = 0
        while case .ladder = step, guardCount < 12 {
            confirmCurrentStep()
            guardCount += 1
        }
        XCTAssertLessThan(guardCount, 12, "ladder did not terminate", file: file, line: line)
    }
}
