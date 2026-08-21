import Foundation

/// Where scripture JSON comes from. The app reads its bundle; tests and tooling
/// read a directory.
public protocol ContentSource: Sendable {
    func data(forResource name: String) throws -> Data
}

public struct ContentError: LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

/// Reads content from a bundle (the shipping configuration).
public struct BundleContentSource: ContentSource {
    private let bundle: Bundle
    private let subdirectory: String?

    public init(bundle: Bundle = .main, subdirectory: String? = "Content") {
        self.bundle = bundle
        self.subdirectory = subdirectory
    }

    public func data(forResource name: String) throws -> Data {
        guard
            let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
                ?? bundle.url(forResource: name, withExtension: "json")
        else {
            throw ContentError("missing bundled content: \(name).json")
        }
        return try Data(contentsOf: url)
    }
}

/// Reads content from a directory on disk (tests, previews, tooling).
public struct DirectoryContentSource: ContentSource {
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func data(forResource name: String) throws -> Data {
        let url = directory.appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ContentError("missing content file: \(url.lastPathComponent)")
        }
        return try Data(contentsOf: url)
    }
}

/// Stands in when content is unavailable; every read fails loudly.
struct UnavailableContentSource: ContentSource {
    func data(forResource name: String) throws -> Data {
        throw ContentError("bundled content is unavailable")
    }
}

/// Loads the manifest eagerly and scripture lazily (§5).
///
/// Two levels of laziness, because the whole Bible is too much to hold at once:
/// a book's JSON is parsed on first touch, and a chapter's verses are tokenised
/// only when that chapter is opened. Showing Genesis 1 does not tokenise the
/// other 49 chapters, let alone the other 65 books.
///
/// Not thread-safe by design: it is owned by the main-actor app state.
open class ContentStore {
    public let manifest: ContentManifest

    private let source: ContentSource
    private let decoder = JSONDecoder()
    private var rawBooks: [BookID: RawBook] = [:]
    private var chapters: [ChapterRef: Chapter] = [:]
    /// Enough for a session, its neighbours, and a plan drawing on a few books.
    private let bookCacheLimit = 3
    private let chapterCacheLimit = 24
    private var bookOrder: [BookID] = []
    private var chapterOrder: [ChapterRef] = []

    public init(source: ContentSource) throws {
        self.source = source
        self.manifest = try decoder.decode(
            ContentManifest.self, from: source.data(forResource: "manifest")
        )
    }

    /// A store with a manifest but no scripture behind it. The app falls back
    /// to this when bundled content cannot be read, so the UI can explain
    /// itself instead of crashing on launch.
    public init(manifest: ContentManifest) {
        self.manifest = manifest
        self.source = UnavailableContentSource()
    }

    public var attributionNotice: String { manifest.attributionNotice }
    public var translationName: String { manifest.name }
    public var translationId: String { manifest.translationId }
    public var books: [BookSummary] { manifest.books }
    public var bookCount: Int { manifest.bookCount }
    public var verseCount: Int { manifest.verseCount }

    public func book(_ id: BookID) -> BookSummary? { manifest.book(id) }
    public func summary(for ref: ChapterRef) -> ChapterSummary? { manifest.chapter(ref) }
    public func title(for ref: ChapterRef) -> String { manifest.title(for: ref) }
    public func title(for ref: VerseRef) -> String { manifest.title(for: ref) }

    // MARK: - Loading

    open func chapter(_ ref: ChapterRef) throws -> Chapter {
        if let cached = chapters[ref] {
            touch(chapter: ref)
            return cached
        }
        guard let bookSummary = manifest.book(ref.book) else {
            throw ContentError("no book \(ref.book.rawValue) in the \(manifest.translationId) manifest")
        }
        let raw = try rawBook(ref.book)
        guard let rawChapter = raw.chapters.first(where: { $0.number == ref.chapter }) else {
            throw ContentError("\(ref.book.rawValue) has no chapter \(ref.chapter)")
        }

        let verses = rawChapter.verses.map { rawVerse in
            Verse(
                ref: VerseRef(ref.book, ref.chapter, rawVerse.number),
                lines: rawVerse.lines,
                startsParagraph: rawVerse.startsParagraph,
                bookOrder: bookSummary.order
            )
        }
        let superscription = rawChapter.superscription.map { text in
            Verse(
                ref: VerseRef(ref.book, ref.chapter, 0),
                lines: [Line(indent: 1, text: text)],
                startsParagraph: false,
                bookOrder: bookSummary.order
            )
        }
        let chapter = Chapter(
            ref: ref,
            superscription: superscription,
            verses: verses,
            stanzas: rawChapter.stanzas
        )

        chapters[ref] = chapter
        chapterOrder.append(ref)
        while chapterOrder.count > chapterCacheLimit {
            chapters.removeValue(forKey: chapterOrder.removeFirst())
        }
        return chapter
    }

    public func verse(_ ref: VerseRef) throws -> Verse {
        guard let verse = try chapter(ref.chapterRef).verse(ref.verse) else {
            throw ContentError("no verse \(ref)")
        }
        return verse
    }

    /// Loads the verses behind a list of references, grouped so each chapter is
    /// touched once. Used by memory plans, which range across books.
    public func verses(for refs: [VerseRef]) throws -> [Verse] {
        var result: [Verse] = []
        result.reserveCapacity(refs.count)
        for ref in refs {
            if let verse = try? verse(ref) { result.append(verse) }
        }
        return result
    }

    private func rawBook(_ id: BookID) throws -> RawBook {
        if let cached = rawBooks[id] {
            bookOrder.removeAll { $0 == id }
            bookOrder.append(id)
            return cached
        }
        let raw = try decoder.decode(
            RawBook.self, from: source.data(forResource: "book-\(id.rawValue)")
        )
        rawBooks[id] = raw
        bookOrder.append(id)
        while bookOrder.count > bookCacheLimit {
            let evicted = bookOrder.removeFirst()
            rawBooks.removeValue(forKey: evicted)
        }
        return raw
    }

    private func touch(chapter ref: ChapterRef) {
        chapterOrder.removeAll { $0 == ref }
        chapterOrder.append(ref)
    }

    // MARK: - Counts

    /// Memorizable units in a chapter, which depends on whether psalm headings
    /// are switched on (§7.5).
    public func unitCount(for ref: ChapterRef, includingSuperscription include: Bool) -> Int {
        guard let summary = manifest.chapter(ref) else { return 0 }
        return summary.verseCount + (include && summary.hasSuperscription ? 1 : 0)
    }
}
