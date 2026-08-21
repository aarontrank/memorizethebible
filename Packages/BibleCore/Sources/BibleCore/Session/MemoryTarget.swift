import Foundation

/// A block of verses recited together: a cumulative pass, a closing recitation,
/// or a unit of review.
public struct MemoryBlock: Hashable, Sendable, Identifiable {
    public let index: Int
    /// "Aleph" for a Psalm 119 stanza, "The Beatitudes" for a plan section,
    /// `nil` for a whole short chapter.
    public let title: String?
    public let units: [VerseRef]

    public var id: Int { index }
    public var isEmpty: Bool { units.isEmpty }

    public init(index: Int, title: String?, units: [VerseRef]) {
        self.index = index
        self.title = title
        self.units = units
    }
}

/// What a session works on, resolved against the content that actually exists.
///
/// A chapter and a memory plan both boil down to the same two things — an
/// ordered list of verses, and the blocks they are recited in — so the session
/// engine only ever sees this and never learns which it was given.
public struct MemoryTarget: Hashable, Sendable {
    public let id: MemoryTargetID
    public let title: String
    /// Every verse to memorize, in the order they will be worked.
    public let units: [VerseRef]
    /// Blocks for cumulative passes and closing recitations.
    public let blocks: [MemoryBlock]

    public init(id: MemoryTargetID, title: String, units: [VerseRef], blocks: [MemoryBlock]) {
        self.id = id
        self.title = title
        self.units = units
        self.blocks = blocks
    }

    public var isEmpty: Bool { units.isEmpty }
    public var chapterRef: ChapterRef? { id.chapterRef }
    public var planID: String? { id.planID }

    /// Chapters the target draws on, in first-appearance order. A plan can
    /// range over many; a chapter target has exactly one.
    public var chapterRefs: [ChapterRef] {
        var seen: Set<ChapterRef> = []
        return units.compactMap { seen.insert($0.chapterRef).inserted ? $0.chapterRef : nil }
    }

    public func block(containing unit: VerseRef) -> MemoryBlock? {
        blocks.first { $0.units.contains(unit) }
    }

    /// Verses recited in the cumulative pass owed after mastering `unit`:
    /// everything in its block up to and including it (§7.1 phase 4, §7.6).
    public func cumulativeUnits(upTo unit: VerseRef) -> [VerseMarker] {
        guard let block = block(containing: unit),
            let position = block.units.firstIndex(of: unit)
        else { return [] }
        return block.units[...position].map { VerseMarker(ref: $0) }
    }

    /// Index of `unit` in the whole target, for "verse 4 of 12" style copy.
    public func position(of unit: VerseRef) -> Int? { units.firstIndex(of: unit) }
}

/// A thin wrapper so cumulative blocks can be compared and hashed as values.
public struct VerseMarker: Hashable, Sendable {
    public let ref: VerseRef
    public init(ref: VerseRef) { self.ref = ref }
}

// MARK: - Building targets

extension MemoryTarget {
    /// A chapter: its verses in order, blocked by stanza where it has them.
    public static func chapter(
        _ chapter: Chapter,
        title: String,
        includingSuperscription include: Bool
    ) -> MemoryTarget {
        let numbers = chapter.unitNumbers(includingSuperscription: include)
        let units = numbers.map { VerseRef(chapter.book, chapter.number, $0) }

        var blocks: [MemoryBlock] = []
        if let stanzas = chapter.stanzas, !stanzas.isEmpty {
            for stanza in stanzas {
                var stanzaUnits = units.filter {
                    $0.verse >= stanza.startVerse && $0.verse <= stanza.endVerse
                }
                // A psalm's heading belongs to the psalm, so it leads the first
                // stanza rather than standing alone.
                if stanza.index == 0, include, chapter.superscription != nil {
                    stanzaUnits.insert(VerseRef(chapter.book, chapter.number, 0), at: 0)
                }
                blocks.append(
                    MemoryBlock(index: stanza.index, title: stanza.title, units: stanzaUnits)
                )
            }
        } else {
            blocks = [MemoryBlock(index: 0, title: nil, units: units)]
        }

        return MemoryTarget(
            id: .chapter(chapter.ref),
            title: title,
            units: units,
            blocks: blocks
        )
    }

    /// A plan: its passages in plan order, blocked by section.
    ///
    /// `availableVerses` filters out anything the translation does not carry —
    /// a plan naming Matthew 17:21 would otherwise point at a verse the BSB
    /// prints empty.
    public static func plan(
        _ plan: MemoryPlan,
        availableVerses: (ChapterRef) -> Set<Int>
    ) -> MemoryTarget {
        var blocks: [MemoryBlock] = []
        var units: [VerseRef] = []
        var seen: Set<VerseRef> = []

        for (index, section) in plan.sections.enumerated() {
            var sectionUnits: [VerseRef] = []
            for passage in section.passages {
                let present = availableVerses(passage.chapterRef)
                for ref in passage.verseRefs where present.contains(ref.verse) {
                    // A plan can name the same verse twice; memorize it once.
                    guard seen.insert(ref).inserted else { continue }
                    sectionUnits.append(ref)
                    units.append(ref)
                }
            }
            guard !sectionUnits.isEmpty else { continue }
            blocks.append(
                MemoryBlock(
                    index: blocks.count,
                    title: plan.sections.count > 1 ? section.title : nil,
                    units: sectionUnits
                )
            )
            _ = index
        }

        return MemoryTarget(id: .plan(plan.id), title: plan.title, units: units, blocks: blocks)
    }
}
