import Foundation

// Read-only scripture, bundled at build time by
// Tools/ContentPipeline/build_content.py. Design doc §6, widened from Psalms
// to the whole Bible.

/// One unit of rendered text. Words are the only maskable kind (§7.2 #4, #5).
public struct Token: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case word
        case punctuation
        /// "Selah" — a liturgical marker, never masked and never memorized.
        case selah
        /// A poetic line break. Carries no text; `indent` gives its depth.
        case lineBreak
    }

    public let kind: Kind
    public let text: String
    /// Whether a space precedes this token when rendered inline.
    public let spaceBefore: Bool
    /// Place in the hiding order, `nil` for every non-word token.
    public let maskIndex: Int?
    /// Indent depth, present on `.lineBreak` tokens only.
    public let indent: Int?

    public init(kind: Kind, text: String, spaceBefore: Bool, maskIndex: Int?, indent: Int? = nil) {
        self.kind = kind
        self.text = text
        self.spaceBefore = spaceBefore
        self.maskIndex = maskIndex
        self.indent = indent
    }

    func withMaskIndex(_ index: Int) -> Token {
        Token(kind: kind, text: text, spaceBefore: spaceBefore, maskIndex: index, indent: indent)
    }

    public var isMaskable: Bool { maskIndex != nil }
}

/// One rendered line of a verse, with its poetic indent. Prose verses are a
/// single line at indent 1.
public struct Line: Hashable, Sendable {
    public let indent: Int
    public let text: String

    public init(indent: Int, text: String) {
        self.indent = indent
        self.text = text
    }
}

/// A verse, or — at number 0 — a psalm's superscription (§7.5).
public struct Verse: Hashable, Sendable, Identifiable {
    public let ref: VerseRef
    public let lines: [Line]
    /// True when the source marks a paragraph break immediately before this verse.
    public let startsParagraph: Bool
    public let tokens: [Token]
    /// Number of maskable words; `maskIndex` values run 0..<wordCount.
    public let wordCount: Int

    public var id: VerseRef { ref }
    public var number: Int { ref.verse }
    public var isSuperscription: Bool { ref.isSuperscription }
    /// Indent of the verse's first line.
    public var indent: Int { lines.first?.indent ?? 1 }

    /// The verse as one flat string: the canonical text for search and for
    /// anything that needs it without markup.
    public var text: String {
        lines.map(\.text).joined(separator: " ")
    }

    public init(ref: VerseRef, lines: [Line], startsParagraph: Bool, bookOrder: Int) {
        self.ref = ref
        self.lines = lines
        self.startsParagraph = startsParagraph
        let seed = MaskOrder.seed(book: bookOrder, chapter: ref.chapter, verse: ref.verse)
        self.tokens = Tokenizer.tokens(for: lines, seed: seed)
        self.wordCount = tokens.reduce(0) { $0 + ($1.kind == .word ? 1 : 0) }
    }
}

/// A stanza boundary. Present only on chapters over the long-chapter threshold,
/// where cumulative review and recitation are scoped to a stanza (§7.6).
public struct Stanza: Hashable, Sendable, Identifiable, Codable {
    public let index: Int
    /// Acrostic letter for Psalm 119 ("Aleph"); `nil` for block-chunked chapters.
    public let title: String?
    public let startVerse: Int
    public let endVerse: Int

    public init(index: Int, title: String?, startVerse: Int, endVerse: Int) {
        self.index = index
        self.title = title
        self.startVerse = startVerse
        self.endVerse = endVerse
    }

    private enum CodingKeys: String, CodingKey {
        case index = "i"
        case title = "t"
        case startVerse = "a"
        case endVerse = "b"
    }

    public var id: Int { index }
    public var verseNumbers: ClosedRange<Int> { startVerse...endVerse }

    public func contains(verse: Int) -> Bool { verse >= startVerse && verse <= endVerse }
}

public struct Chapter: Hashable, Sendable, Identifiable {
    public let ref: ChapterRef
    public let superscription: Verse?
    public let verses: [Verse]
    public let stanzas: [Stanza]?

    public var id: ChapterRef { ref }
    public var book: BookID { ref.book }
    public var number: Int { ref.chapter }
    public var verseCount: Int { verses.count }
    public var isStanzaScoped: Bool { stanzas?.isEmpty == false }

    public init(ref: ChapterRef, superscription: Verse?, verses: [Verse], stanzas: [Stanza]?) {
        self.ref = ref
        self.superscription = superscription
        self.verses = verses
        self.stanzas = stanzas
    }

    public func verse(_ number: Int) -> Verse? {
        number == 0 ? superscription : verses.first { $0.number == number }
    }

    /// Verse numbers in order. Not always 1...n: the BSB omits sixteen New
    /// Testament verses, leaving deliberate gaps.
    public var verseNumbers: [Int] { verses.map(\.number) }

    /// Memorizable units, optionally including the superscription (§7.5).
    public func unitNumbers(includingSuperscription include: Bool) -> [Int] {
        if include, superscription != nil { return [0] + verseNumbers }
        return verseNumbers
    }

    public func stanza(containing verse: Int) -> Stanza? {
        stanzas?.first { $0.contains(verse: verse) }
    }

    /// Verses a cumulative pass covers after mastering `verse`: from the start
    /// of the chapter, or of the current stanza for a long one (§7.6).
    public func cumulativeUnits(upTo verse: Int, includingSuperscription include: Bool) -> [Int] {
        let units = unitNumbers(includingSuperscription: include)
        guard let stanza = stanza(containing: verse) else {
            return units.filter { $0 <= verse }
        }
        return units.filter { $0 >= stanza.startVerse && $0 <= verse }
    }
}

// MARK: - Manifest

/// A chapter as it appears in the manifest: enough to list and count, with no
/// verse text loaded.
public struct ChapterSummary: Hashable, Sendable, Codable, Identifiable {
    public let number: Int
    public let verseCount: Int
    public let firstVerse: Int
    public let hasSuperscription: Bool
    public let firstLine: String
    public let stanzas: [Stanza]?

    public var id: Int { number }

    private enum CodingKeys: String, CodingKey {
        case number = "n"
        case verseCount, firstVerse, hasSuperscription, firstLine, stanzas
    }
}

public struct BookSummary: Hashable, Sendable, Codable, Identifiable {
    public let id: BookID
    public let name: String
    /// Canonical position, 1...66. Also seeds the mask ordering.
    public let order: Int
    public let testament: Testament
    public let chapters: [ChapterSummary]

    public var chapterCount: Int { chapters.count }
    public var verseCount: Int { chapters.reduce(0) { $0 + $1.verseCount } }

    public func chapter(_ number: Int) -> ChapterSummary? {
        chapters.first { $0.number == number }
    }
}

/// Translation metadata plus the whole index (§6, §11).
public struct ContentManifest: Hashable, Sendable, Codable {
    public let schemaVersion: Int
    public let translationId: String
    public let name: String
    /// Rendered verbatim on the About screen (§4, §8.4).
    public let attributionNotice: String
    public let longChapterVerseThreshold: Int
    public let bookCount: Int
    public let chapterCount: Int
    public let verseCount: Int
    public let books: [BookSummary]

    public init(
        schemaVersion: Int,
        translationId: String,
        name: String,
        attributionNotice: String,
        longChapterVerseThreshold: Int,
        bookCount: Int,
        chapterCount: Int,
        verseCount: Int,
        books: [BookSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.translationId = translationId
        self.name = name
        self.attributionNotice = attributionNotice
        self.longChapterVerseThreshold = longChapterVerseThreshold
        self.bookCount = bookCount
        self.chapterCount = chapterCount
        self.verseCount = verseCount
        self.books = books
    }

    public func book(_ id: BookID) -> BookSummary? { books.first { $0.id == id } }

    public func chapter(_ ref: ChapterRef) -> ChapterSummary? {
        book(ref.book)?.chapter(ref.chapter)
    }

    public func books(in testament: Testament) -> [BookSummary] {
        books.filter { $0.testament == testament }.sorted { $0.order < $1.order }
    }

    /// "Psalm 23" for Psalms, "Romans 8" elsewhere — psalms are spoken of by
    /// number rather than as chapters.
    public func title(for ref: ChapterRef) -> String {
        guard let book = book(ref.book) else { return "\(ref.book.rawValue) \(ref.chapter)" }
        if book.id == .psalms { return "Psalm \(ref.chapter)" }
        return "\(book.name) \(ref.chapter)"
    }

    public func title(for ref: VerseRef) -> String {
        "\(title(for: ref.chapterRef)):\(ref.verse)"
    }

    /// "Romans 10:9–10" for a passage, collapsing single verses.
    public func title(for passage: PassageRef) -> String {
        let base = title(for: passage.chapterRef)
        return passage.isSingleVerse
            ? "\(base):\(passage.firstVerse)"
            : "\(base):\(passage.firstVerse)–\(passage.lastVerse)"
    }
}

// MARK: - On-disk shapes
//
// The bundle stores text and structure only; tokens are built on load. Keys are
// short because they repeat 31,000 times.

struct RawVerse: Decodable {
    let number: Int
    let lines: [Line]
    let startsParagraph: Bool

    private enum CodingKeys: String, CodingKey {
        case number = "n"
        case lines
        case startsParagraph = "p"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        startsParagraph = (try container.decodeIfPresent(Int.self, forKey: .startsParagraph) ?? 0) == 1
        // Each line is a two-element array: [indent, text].
        var lineContainer = try container.nestedUnkeyedContainer(forKey: .lines)
        var lines: [Line] = []
        while !lineContainer.isAtEnd {
            var pair = try lineContainer.nestedUnkeyedContainer()
            let indent = try pair.decode(Int.self)
            let text = try pair.decode(String.self)
            lines.append(Line(indent: indent, text: text))
        }
        self.lines = lines
    }
}

struct RawChapter: Decodable {
    let number: Int
    let superscription: String?
    let verses: [RawVerse]
    let stanzas: [Stanza]?

    private enum CodingKeys: String, CodingKey {
        case number = "n"
        case superscription = "d"
        case verses, stanzas
    }
}

struct RawBook: Decodable {
    let id: BookID
    let chapters: [RawChapter]
}
