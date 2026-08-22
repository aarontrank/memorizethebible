import Foundation

/// Which tokens must stay on a line together.
///
/// Text is drawn token by token so each word can be masked on its own, which
/// means the layout could otherwise break anywhere — including before a comma,
/// leaving it dangling at the start of the next line. Punctuation belongs to
/// the word it sits against, so the two wrap as one.
///
/// This lives here, rather than inside the layout, because it is a rule about
/// text rather than about SwiftUI, and because a rule worth having is worth
/// testing against all 31,086 verses.
public enum LineWrapping {
    /// A group index per token. Tokens sharing an index must be placed on the
    /// same line; a line may only break between groups.
    public static func groupIndices(for tokens: [Token]) -> [Int] {
        guard !tokens.isEmpty else { return [] }

        // First pass: a space is the only place a break could go, so a token
        // with no space before it joins whatever it follows.
        var groups: [Int] = []
        var current = 0
        for (offset, token) in tokens.enumerated() {
            if token.kind == .lineBreak {
                current += 1
                groups.append(current)
                current += 1
                continue
            }
            if offset > 0, token.spaceBefore {
                current += 1
            }
            groups.append(current)
        }

        // Second pass: punctuation with a space on both sides — a dash standing
        // alone, say — has nothing holding it, so it joins the group before it
        // rather than being left to start a line by itself. An opening quote is
        // not this case: it has no space after it, so the first pass has
        // already tied it to the word that follows.
        var result = groups
        var index = 0
        while index < tokens.count {
            let group = result[index]
            var end = index
            while end + 1 < tokens.count, result[end + 1] == group { end += 1 }
            defer { index = end + 1 }

            let members = tokens[index...end]
            guard members.allSatisfy({ $0.kind == .punctuation }) else { continue }
            // Nothing before it on this line to attach to.
            guard index > 0, tokens[index - 1].kind != .lineBreak else { continue }
            let previous = result[index - 1]
            for position in index...end { result[position] = previous }
        }
        return result
    }

    /// The tokens grouped, for callers that want them directly.
    public static func groups(for tokens: [Token]) -> [[Int]] {
        let indices = groupIndices(for: tokens)
        var groups: [[Int]] = []
        for (offset, group) in indices.enumerated() {
            if offset > 0, group == indices[offset - 1] {
                groups[groups.count - 1].append(offset)
            } else {
                groups.append([offset])
            }
        }
        return groups
    }
}
