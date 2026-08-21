import Foundation

/// Splits verse text into the tokens the renderer masks (§7.2).
///
/// This used to run at build time and ship in the bundle. It moved to the
/// runtime when the app grew from Psalms to the whole Bible: pre-tokenised
/// JSON for 31,000 verses came to roughly 45 MB, against 5 MB for text plus
/// structure. The rules are unchanged, and `TokenizerTests` checks them against
/// the whole corpus.
public enum Tokenizer {
    /// Word characters: letters, digits, and Latin-1/Latin-Extended accents.
    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true  // 0-9 A-Z a-z
        case 0xC0...0x24F: return true  // Latin-1 Supplement and Latin Extended-A/B
        default: return false
        }
    }

    /// Characters that join two word parts: apostrophes and hyphens, as in
    /// "LORD's" and "loving-kindness".
    private static func isJoinScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "'", "\u{2019}", "-", "\u{2010}", "\u{2011}": return true
        default: return false
        }
    }

    private static let selahWords: Set<String> = ["selah"]

    /// Tokenises one line of scripture. Word tokens come back with a `nil`
    /// `maskIndex`; `assignMaskIndices` fills those in for the whole verse.
    static func tokens(in line: String) -> [Token] {
        var tokens: [Token] = []
        var pendingSpace = false
        let scalars = Array(line.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSpace = true
                index += 1
                continue
            }

            if isWordScalar(scalar) {
                var end = index
                while end < scalars.count {
                    if isWordScalar(scalars[end]) {
                        end += 1
                    } else if isJoinScalar(scalars[end]),
                        end + 1 < scalars.count,
                        isWordScalar(scalars[end + 1])
                    {
                        // A join only counts when a word continues after it, so
                        // a trailing dash stays punctuation.
                        end += 2
                    } else {
                        break
                    }
                }
                // A possessive can end the word: "the LORD's".
                if end < scalars.count, scalars[end] == "'" || scalars[end] == "\u{2019}" {
                    let next = end + 1 < scalars.count ? scalars[end + 1] : " "
                    if !isWordScalar(next) { end += 1 }
                }
                let text = String(String.UnicodeScalarView(scalars[index..<end]))
                tokens.append(
                    Token(
                        kind: selahWords.contains(text.lowercased()) ? .selah : .word,
                        text: text,
                        spaceBefore: pendingSpace,
                        maskIndex: nil
                    )
                )
                pendingSpace = false
                index = end
                continue
            }

            // Everything else is punctuation. A run of it with no whitespace
            // between becomes one token, so `.”` stays together.
            var end = index
            while end < scalars.count,
                !CharacterSet.whitespacesAndNewlines.contains(scalars[end]),
                !isWordScalar(scalars[end])
            {
                end += 1
            }
            tokens.append(
                Token(
                    kind: .punctuation,
                    text: String(String.UnicodeScalarView(scalars[index..<end])),
                    spaceBefore: pendingSpace,
                    maskIndex: nil
                )
            )
            pendingSpace = false
            index = end
        }

        return tokens
    }

    /// Tokenises a verse's lines, inserting a line break between them.
    static func tokens(for lines: [Line], seed: UInt32) -> [Token] {
        var tokens: [Token] = []
        for (offset, line) in lines.enumerated() {
            if offset > 0 {
                tokens.append(
                    Token(kind: .lineBreak, text: "", spaceBefore: false, maskIndex: nil, indent: line.indent)
                )
            }
            tokens.append(contentsOf: self.tokens(in: line.text))
        }
        return assignMaskIndices(tokens, seed: seed)
    }

    /// Assigns each maskable word its place in the hiding order (§7.2 #5:
    /// Selah and punctuation are never maskable).
    static func assignMaskIndices(_ tokens: [Token], seed: UInt32) -> [Token] {
        var tokens = tokens
        let positions = tokens.indices.filter { tokens[$0].kind == .word }
        let order = MaskOrder.order(count: positions.count, seed: seed)
        for (rank, slot) in order.enumerated() {
            tokens[positions[slot]] = tokens[positions[slot]].withMaskIndex(rank)
        }
        return tokens
    }
}

/// The deterministic, distributed hiding order (§7.2 #1 and #3).
///
/// No randomness anywhere: the order is a pure function of the verse's
/// reference, so the same words hide at the same level on every device and
/// every launch, forever.
public enum MaskOrder {
    private static let goldenRatioConjugate = 0.618_033_988_749_894_9

    /// Stable 32-bit seed for a verse. `book` is the book's canonical order,
    /// 1...66, so two books never share a verse's ordering.
    public static func seed(book: Int, chapter: Int, verse: Int) -> UInt32 {
        var x = UInt32(truncatingIfNeeded: book &* 1_000_003 &+ chapter &* 10007 &+ verse &* 61 &+ 1)
        x ^= x >> 15
        x = x &* 2_246_822_519
        x ^= x >> 13
        x = x &* 3_266_489_917
        x ^= x >> 16
        return x
    }

    /// An ordering of 0..<count whose every prefix is spread across the verse.
    ///
    /// A golden-ratio (low-discrepancy) additive sequence with linear probing.
    /// The property that matters: the first k entries are k positions spread
    /// through the verse rather than clustered at the front, so level 1 masks
    /// 25% of the words evenly rather than blanking the opening clause.
    public static func order(count: Int, seed: UInt32) -> [Int] {
        guard count > 0 else { return [] }
        var taken = [Bool](repeating: false, count: count)
        var order: [Int] = []
        order.reserveCapacity(count)
        var x = Double(seed % 1_000_003) / 1_000_003.0

        for _ in 0..<count {
            x = (x + goldenRatioConjugate).truncatingRemainder(dividingBy: 1.0)
            var position = min(Int(x * Double(count)), count - 1)
            while taken[position] {
                position = (position + 1) % count
            }
            taken[position] = true
            order.append(position)
        }
        return order
    }
}
