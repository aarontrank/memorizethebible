import Foundation

/// The five rungs of the recall ladder (§7.1).
public enum MaskLevel: Int, CaseIterable, Codable, Sendable, Comparable {
    /// Full text. Phase 1, reading.
    case none = 0
    case quarter = 1
    case half = 2
    case threeQuarters = 3
    /// Every word hidden. Mastery is only ever conferred from here.
    case full = 4

    public static func < (lhs: MaskLevel, rhs: MaskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// "Show more" reveals words by stepping DOWN a level (§7.1).
    public var showingMore: MaskLevel { MaskLevel(rawValue: rawValue - 1) ?? .none }
    /// "Show less" hides words by stepping UP a level.
    public var showingLess: MaskLevel { MaskLevel(rawValue: rawValue + 1) ?? .full }

    public var isFullyMasked: Bool { self == .full }

    /// Percentage of words hidden, for the level indicator's accessibility label.
    public var percentMasked: Int { rawValue * 25 }
}

/// The runtime masking rule (§7.2).
///
/// There is no randomness here: `maskIndex` is baked into the content at build
/// time, seeded by (psalmNumber, verseNumber), so a given word is hidden at a
/// given level on every device, every launch, forever. Randomizing per session
/// would destroy the learning signal.
public enum Masking {
    /// How many words are hidden at `level`, i.e. `ceil(level / 4 * wordCount)`.
    /// Computed in integer arithmetic so it can never drift by a rounding error.
    public static func maskedWordCount(wordCount: Int, level: MaskLevel) -> Int {
        guard wordCount > 0 else { return 0 }
        return (level.rawValue * wordCount + 3) / 4
    }

    public static func isMasked(_ token: Token, level: MaskLevel, wordCount: Int) -> Bool {
        guard let index = token.maskIndex else { return false }
        return index < maskedWordCount(wordCount: wordCount, level: level)
    }

    /// Masked/unmasked flags for a verse at a level, in token order.
    public static func mask(_ verse: Verse, level: MaskLevel) -> [Bool] {
        let threshold = maskedWordCount(wordCount: verse.wordCount, level: level)
        return verse.tokens.map { token in
            guard let index = token.maskIndex else { return false }
            return index < threshold
        }
    }

    /// What VoiceOver reads for a verse (§12): the visible text, with every
    /// masked word spoken as "blank". The verse is one accessibility element,
    /// so this is the whole label.
    public static func spokenText(_ verse: Verse, level: MaskLevel, blankWord: String = "blank") -> String {
        var parts: [String] = []
        if !verse.isSuperscription { parts.append("Verse \(verse.number).") }
        let threshold = maskedWordCount(wordCount: verse.wordCount, level: level)
        for token in verse.tokens {
            switch token.kind {
            case .lineBreak, .punctuation:
                // Punctuation is scaffolding, not content; VoiceOver applies its
                // own pauses from the text it is given.
                continue
            case .selah:
                parts.append(token.text)
            case .word:
                guard let index = token.maskIndex else {
                    parts.append(token.text)
                    continue
                }
                parts.append(index < threshold ? blankWord : token.text)
            }
        }
        return parts.joined(separator: " ")
    }

    /// The verse rendered as plain text with hidden words replaced by
    /// underscores. Used by tests and by VoiceOver fallbacks.
    public static func plainText(_ verse: Verse, level: MaskLevel, blank: String = "____") -> String {
        var out = ""
        let threshold = maskedWordCount(wordCount: verse.wordCount, level: level)
        for token in verse.tokens {
            if token.kind == .lineBreak {
                out += "\n"
                continue
            }
            if token.spaceBefore, !out.isEmpty, !out.hasSuffix("\n") { out += " " }
            if let index = token.maskIndex, index < threshold {
                out += blank
            } else {
                out += token.text
            }
        }
        return out
    }
}
