import Foundation

/// A book of the Bible, identified by its three-letter USFM code ("PSA").
public struct BookID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue.uppercased() }
    public init(_ rawValue: String) { self.init(rawValue: rawValue) }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let psalms = BookID("PSA")
}

public enum Testament: String, Codable, Sendable, CaseIterable {
    case old
    case new

    public var title: String {
        switch self {
        case .old: return "Old Testament"
        case .new: return "New Testament"
        }
    }
}

/// A chapter, anywhere in the Bible.
public struct ChapterRef: Hashable, Sendable, Codable, Comparable {
    public let book: BookID
    public let chapter: Int

    public init(_ book: BookID, _ chapter: Int) {
        self.book = book
        self.chapter = chapter
    }

    public static func < (lhs: ChapterRef, rhs: ChapterRef) -> Bool {
        (lhs.book.rawValue, lhs.chapter) < (rhs.book.rawValue, rhs.chapter)
    }

    /// "PSA 23", for use as a JSON object key.
    public var storageKey: String { "\(book.rawValue) \(chapter)" }

    public init?(storageKey: String) {
        let parts = storageKey.split(separator: " ")
        guard parts.count == 2, let chapter = Int(parts[1]) else { return nil }
        self.init(BookID(String(parts[0])), chapter)
    }
}

/// A single verse, anywhere in the Bible. Verse 0 is a psalm's superscription
/// (§7.5).
///
/// This is the key everything hangs on: verse mastery is recorded globally by
/// reference, so a verse learned inside a memory plan is the same verse — and
/// the same progress — as one learned by working through its chapter.
public struct VerseRef: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let book: BookID
    public let chapter: Int
    public let verse: Int

    public init(_ book: BookID, _ chapter: Int, _ verse: Int) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    public var chapterRef: ChapterRef { ChapterRef(book, chapter) }
    public var isSuperscription: Bool { verse == 0 }

    /// Sorting is by book code, which is not canonical order; use the manifest's
    /// book order when presentation order matters.
    public static func < (lhs: VerseRef, rhs: VerseRef) -> Bool {
        (lhs.book.rawValue, lhs.chapter, lhs.verse)
            < (rhs.book.rawValue, rhs.chapter, rhs.verse)
    }

    public var description: String { "\(book.rawValue) \(chapter):\(verse)" }

    // MARK: - Dictionary-friendly encoding
    //
    // Progress keys verse states by reference, and JSON object keys must be
    // strings, so a reference round-trips through "PSA 23:1".

    public var storageKey: String { "\(book.rawValue) \(chapter):\(verse)" }

    public init?(storageKey: String) {
        let parts = storageKey.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let numbers = parts[1].split(separator: ":")
        guard numbers.count == 2,
            let chapter = Int(numbers[0]),
            let verse = Int(numbers[1])
        else { return nil }
        self.init(BookID(String(parts[0])), chapter, verse)
    }
}

/// A contiguous run of verses within one chapter, e.g. Romans 10:9–10.
public struct PassageRef: Hashable, Sendable, Codable {
    public let book: BookID
    public let chapter: Int
    public let firstVerse: Int
    public let lastVerse: Int

    public init(_ book: BookID, _ chapter: Int, _ firstVerse: Int, _ lastVerse: Int? = nil) {
        self.book = book
        self.chapter = chapter
        self.firstVerse = firstVerse
        self.lastVerse = max(lastVerse ?? firstVerse, firstVerse)
    }

    public var chapterRef: ChapterRef { ChapterRef(book, chapter) }
    public var isSingleVerse: Bool { firstVerse == lastVerse }

    /// Verse references in the passage. Numbering can have gaps where the BSB
    /// omits a verse, so callers should intersect this with the chapter's real
    /// verse numbers.
    public var verseRefs: [VerseRef] {
        (firstVerse...lastVerse).map { VerseRef(book, chapter, $0) }
    }
}
