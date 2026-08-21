import SwiftUI

/// Per-token layout hints, read by `FlowLayout`.
private struct TokenLineBreakKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

private struct TokenIndentKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

private struct TokenSpaceBeforeKey: LayoutValueKey {
    static let defaultValue: Bool = false
}

/// Tokens sharing a group must stay on one line; see `LineWrapping`.
private struct TokenGroupKey: LayoutValueKey {
    static let defaultValue: Int = -1
}

extension View {
    /// Marks this subview as a poetic line break rather than drawn content.
    func tokenLineBreak(_ isBreak: Bool, indent: Int) -> some View {
        layoutValue(key: TokenLineBreakKey.self, value: isBreak)
            .layoutValue(key: TokenIndentKey.self, value: indent)
    }

    func tokenSpaceBefore(_ spaceBefore: Bool) -> some View {
        layoutValue(key: TokenSpaceBeforeKey.self, value: spaceBefore)
    }

    func tokenIndent(_ indent: Int) -> some View {
        layoutValue(key: TokenIndentKey.self, value: indent)
    }

    /// Ties this token to its neighbours so a line cannot break between them.
    func tokenGroup(_ group: Int) -> some View {
        layoutValue(key: TokenGroupKey.self, value: group)
    }
}

/// Lays word and punctuation tokens out as flowing text with explicit poetic
/// line breaks.
///
/// This is what makes §7.2 #2 — layout stability — structural rather than
/// hopeful. Every token keeps its natural size whether it is masked or not
/// (a blank is the same word drawn invisibly), so line breaking is identical
/// at every mask level, at every Dynamic Type size.
///
/// Because each token is placed separately, a line could otherwise break
/// anywhere — including before a comma, stranding it at the start of the next
/// line. Tokens carry a group from `LineWrapping`, and a break may only happen
/// between groups, so punctuation always wraps with the word it belongs to.
struct FlowLayout: Layout {
    /// Extra space between rendered lines, on top of each line's own height.
    var lineSpacing: CGFloat
    /// Width of an inter-word space in the current scripture font.
    var spaceWidth: CGFloat
    /// Width of one poetic indent step.
    var indentWidth: CGFloat

    struct Row {
        var indices: [Int] = []
        var offsets: [CGFloat] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var indent: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layoutRows(subviews: subviews, maxWidth: maxWidth)
        let height =
            rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        // Claim the whole width offered rather than shrink-wrapping the widest
        // row. Shrink-wrapping hands placement a bounds equal to that row's
        // exact extent, so the last group on it lands a rounding error past the
        // edge, wraps, and draws a line lower than the height reported here —
        // on top of the verse below. Filling makes both passes measure the same
        // number. With an unspecified width there is nothing to fill, so the
        // natural extent stands.
        guard maxWidth != .infinity else {
            return CGSize(width: rows.map { $0.indent + $0.width }.max() ?? 0, height: height)
        }
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        // The same width both passes measured with. Sizing sees the proposal
        // and placement sees the bounds, and if those ever differ by a point
        // the two disagree about where a line breaks — the reported height is
        // then a line short and the verse draws over the one beneath it.
        let rows = layoutRows(subviews: subviews, maxWidth: proposal.width ?? bounds.width)
        var y = bounds.minY
        for row in rows {
            for (index, offset) in zip(row.indices, row.offsets) {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + row.indent + offset, y: y + row.height / 2),
                    anchor: .leading,
                    proposal: ProposedViewSize(size)
                )
            }
            y += row.height + lineSpacing
        }
    }

    private func layoutRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        var currentIndent = CGFloat(subviews.first?[TokenIndentKey.self] ?? 1) - 1
        // The indent this poetic line started at. A line that runs out of width
        // continues one step in from *this*, not one step in from wherever the
        // previous wrap left off — otherwise a long line at a large type size
        // walks steadily across the screen.
        var baseIndent = currentIndent

        func flush(nextIndent: CGFloat) {
            row.width = x
            row.indent = currentIndent * indentWidth
            if row.height == 0 { row.height = lineHeightFallback(subviews: subviews) }
            rows.append(row)
            row = Row()
            // A line that wraps because it ran out of width is continued one
            // step further in, so poetic structure stays readable.
            currentIndent = nextIndent
            x = 0
        }

        for group in groups(in: subviews) {
            if group.isLineBreak {
                baseIndent = CGFloat(group.indent) - 1
                flush(nextIndent: baseIndent)
                continue
            }

            let needsSpace = group.spaceBefore && !row.indices.isEmpty
            let leading = needsSpace ? spaceWidth : 0
            let available = maxWidth - currentIndent * indentWidth

            if !row.indices.isEmpty, x + leading + group.width > available {
                flush(nextIndent: baseIndent + 1)
                place(group, startingAt: 0, in: &row, x: &x)
            } else {
                place(group, startingAt: x + leading, in: &row, x: &x)
            }
        }

        if !row.indices.isEmpty || rows.isEmpty {
            row.width = x
            row.indent = currentIndent * indentWidth
            if row.height == 0 { row.height = lineHeightFallback(subviews: subviews) }
            rows.append(row)
        }
        return rows
    }

    private func place(_ group: Group, startingAt start: CGFloat, in row: inout Row, x: inout CGFloat) {
        var offset = start
        for (position, index) in group.indices.enumerated() {
            offset += group.leadings[position]
            row.indices.append(index)
            row.offsets.append(offset)
            offset += group.widths[position]
        }
        row.height = max(row.height, group.height)
        x = offset
    }

    /// Runs of subviews that must be placed together, in order.
    private func groups(in subviews: Subviews) -> [Group] {
        var groups: [Group] = []
        var current: Group?

        func flush() {
            if let current { groups.append(current) }
            current = nil
        }

        for index in subviews.indices {
            let subview = subviews[index]
            if subview[TokenLineBreakKey.self] {
                flush()
                groups.append(Group(isLineBreak: true, indent: subview[TokenIndentKey.self]))
                continue
            }
            let size = subview.sizeThatFits(.unspecified)
            let groupID = subview[TokenGroupKey.self]
            // A group value of -1 means the caller did not group its tokens, in
            // which case fall back to breaking wherever there is a space.
            let startsNew = current == nil
                || (groupID < 0 ? subview[TokenSpaceBeforeKey.self] : groupID != current?.group)
            if startsNew {
                flush()
                current = Group(
                    group: groupID,
                    indent: subview[TokenIndentKey.self],
                    spaceBefore: subview[TokenSpaceBeforeKey.self]
                )
            }
            var building = current ?? Group()
            // A group can span a space of its own — "day — night" is held
            // together so the dash never starts a line, and the spaces around
            // it still have to be drawn.
            let leading = building.indices.isEmpty || !subview[TokenSpaceBeforeKey.self]
                ? 0
                : spaceWidth
            building.indices.append(index)
            building.leadings.append(leading)
            building.widths.append(size.width)
            building.width += leading + size.width
            building.height = max(building.height, size.height)
            current = building
        }
        flush()
        return groups
    }

    private struct Group {
        var isLineBreak = false
        var group = -1
        var indent = 1
        var spaceBefore = false
        var indices: [Int] = []
        /// Space to leave before each member, for groups that span a space.
        var leadings: [CGFloat] = []
        var widths: [CGFloat] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lineHeightFallback(subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(.unspecified).height ?? 0
    }
}
