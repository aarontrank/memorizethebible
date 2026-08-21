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
}

/// Lays word and punctuation tokens out as flowing text with explicit poetic
/// line breaks.
///
/// This is what makes §7.2 #2 — layout stability — structural rather than
/// hopeful. Every token keeps its natural size whether it is masked or not
/// (a blank is the same word drawn invisibly), so line breaking is identical
/// at every mask level, at every Dynamic Type size.
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
        let width = rows.map { $0.indent + $0.width }.max() ?? 0
        return CGSize(width: min(width, maxWidth == .infinity ? width : maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = layoutRows(subviews: subviews, maxWidth: bounds.width)
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

        func flush(nextIndent: CGFloat, isWrap: Bool) {
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

        for index in subviews.indices {
            let subview = subviews[index]
            if subview[TokenLineBreakKey.self] {
                flush(nextIndent: CGFloat(subview[TokenIndentKey.self]) - 1, isWrap: false)
                continue
            }

            let size = subview.sizeThatFits(.unspecified)
            let needsSpace = subview[TokenSpaceBeforeKey.self] && !row.indices.isEmpty
            let leading = needsSpace ? spaceWidth : 0
            let available = maxWidth - currentIndent * indentWidth

            if !row.indices.isEmpty, x + leading + size.width > available {
                flush(nextIndent: currentIndent + 1, isWrap: true)
                row.indices.append(index)
                row.offsets.append(0)
                row.height = max(row.height, size.height)
                x = size.width
                continue
            }

            row.indices.append(index)
            row.offsets.append(x + leading)
            row.height = max(row.height, size.height)
            x += leading + size.width
        }

        if !row.indices.isEmpty || rows.isEmpty {
            row.width = x
            row.indent = currentIndent * indentWidth
            if row.height == 0 { row.height = lineHeightFallback(subviews: subviews) }
            rows.append(row)
        }
        return rows
    }

    private func lineHeightFallback(subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(.unspecified).height ?? 0
    }
}
