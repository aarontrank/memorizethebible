import Foundation

/// Masking across a block of verses rather than a single one (Review mode).
///
/// Each verse keeps its own deterministic mask ordering, so the same words
/// vanish at the same level every time, exactly as in a session (§7.2 #1). What
/// changes is scope: every verse in the block is masked at once, so the level
/// describes the whole passage instead of one line of it.
public enum BlockMasking {
    /// Total maskable words across the block.
    public static func wordCount(_ verses: [Verse]) -> Int {
        verses.reduce(0) { $0 + $1.wordCount }
    }

    /// Words hidden across the block at this level.
    public static func maskedWordCount(_ verses: [Verse], level: MaskLevel) -> Int {
        verses.reduce(0) { $0 + Masking.maskedWordCount(wordCount: $1.wordCount, level: level) }
    }

    /// The block rendered as plain text with hidden words blanked, one entry
    /// per verse. Used by tests and by VoiceOver.
    public static func plainText(_ verses: [Verse], level: MaskLevel) -> [String] {
        verses.map { Masking.plainText($0, level: level) }
    }

    /// What VoiceOver reads for the block (§12).
    public static func spokenText(_ verses: [Verse], level: MaskLevel) -> String {
        verses.map { Masking.spokenText($0, level: level) }.joined(separator: " ")
    }
}
