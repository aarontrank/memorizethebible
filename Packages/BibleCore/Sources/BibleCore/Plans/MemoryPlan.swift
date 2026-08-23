import Foundation

/// Where a plan came from. Built-in plans are marked separately; this
/// distinguishes the ones you wrote from the ones someone sent you.
public enum PlanOrigin: String, Codable, Hashable, Sendable {
    case own
    case shared
}

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
    /// Only meaningful for plans that are not built in.
    public var origin: PlanOrigin
    public var createdAt: Date?

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        sections: [Section],
        isBuiltIn: Bool = false,
        origin: PlanOrigin = .own,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sections = sections
        self.isBuiltIn = isBuiltIn
        self.origin = origin
        self.createdAt = createdAt
    }

    // Written by hand for one reason: `origin` arrived after plans were already
    // on disk, and a plan saved before it must still decode. A throw here would
    // take the whole progress file with it.
    private enum CodingKeys: String, CodingKey {
        case id, title, summary, sections, isBuiltIn, origin, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        origin = try container.decodeIfPresent(PlanOrigin.self, forKey: .origin) ?? .own
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// Convenience for a plan that needs no sections.
    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String = "",
        passages: [PassageRef],
        isBuiltIn: Bool = false,
        origin: PlanOrigin = .own,
        createdAt: Date? = nil
    ) {
        self.init(
            id: id,
            title: title,
            summary: summary,
            sections: [Section(id: "\(id)-all", title: title, passages: passages)],
            isBuiltIn: isBuiltIn,
            origin: origin,
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
