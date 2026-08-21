import Foundation

/// Every tunable number in the memorization loop, named rather than sprinkled
/// as literals (§7.1: "3 is the default; make it a constant, not a magic
/// number").
public enum SessionRules {
    /// Reads required at level 0 before the recall ladder unlocks (§7.1).
    public static let requiredReads = 3

    /// Where a failed cumulative pass drops to for a supported run (§7.1).
    public static let supportedCumulativeLevel = MaskLevel.half

    /// Verse count above which cumulative review is scoped to a stanza (§7.6).
    /// The content pipeline uses the same threshold when emitting stanzas.
    public static let longChapterVerseThreshold = 40
}
