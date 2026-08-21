import Foundation

/// A curated set of verses to memorize together: the Roman Road, the Sermon on
/// the Mount, or anything the user assembles.
///
/// A plan is only an ordering over references. It owns no progress of its own —
/// mastery lives against the verse, so a verse learned in a plan is already
/// learned in its chapter, and the same verse appearing in two plans is learned
/// once.
public struct MemoryPlan: Codable, Hashable, Sendable, Identifiable {
    /// A named run of passages inside a plan, e.g. "The Beatitudes".
    public struct Section: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public var title: String
        public var passages: [PassageRef]

        public init(id: String = UUID().uuidString, title: String, passages: [PassageRef]) {
            self.id = id
            self.title = title
            self.passages = passages
        }
    }

    public let id: String
    public var title: String
    /// One or two sentences on what the plan is for, shown on its detail screen.
    public var summary: String
    public var sections: [Section]
    /// True for plans that ship with the app; those cannot be edited, only
    /// hidden.
    public let isBuiltIn: Bool
    public var createdAt: Date?

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        sections: [Section],
        isBuiltIn: Bool = false,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sections = sections
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    /// Convenience for a plan that needs no sections.
    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        passages: [PassageRef],
        isBuiltIn: Bool = false,
        createdAt: Date? = nil
    ) {
        self.init(
            id: id,
            title: title,
            summary: summary,
            sections: [Section(id: "\(id)-all", title: title, passages: passages)],
            isBuiltIn: isBuiltIn,
            createdAt: createdAt
        )
    }

    public var passages: [PassageRef] { sections.flatMap(\.passages) }

    /// Every verse the plan names, in plan order, before checking which of them
    /// the translation actually has.
    public var declaredVerseRefs: [VerseRef] { passages.flatMap(\.verseRefs) }

    public var chapterRefs: [ChapterRef] {
        var seen: Set<ChapterRef> = []
        return passages.compactMap { seen.insert($0.chapterRef).inserted ? $0.chapterRef : nil }
    }

    public var isEmpty: Bool { passages.isEmpty }
}
