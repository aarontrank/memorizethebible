import BibleCore
import SwiftUI

/// How a verse is presented in the running text.
enum VerseEmphasis {
    /// The verse being worked on: full opacity.
    case active
    /// Context: dimmed but readable. §8.2 — you always see the whole psalm.
    case dimmed
}

/// One verse, rendered at a mask level (milestone M3).
///
/// The masking trick that guarantees §7.2 #2: a masked word is the *same word*,
/// drawn transparently over a blank fill. Nothing is substituted, so nothing
/// can reflow — at any mask level, at any Dynamic Type size.
struct VerseView: View {
    let verse: Verse
    let level: MaskLevel
    var emphasis: VerseEmphasis = .active
    var textStyle: Font.TextStyle = .body
    /// Marks a verse already memorized somewhere else and not yet worked here.
    var isCarriedOver: Bool = false
    /// Nil where peeking is meaningless, such as a dimmed context verse.
    var onPeek: (() -> Void)?

    @State private var peekedTokens: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Computed once per body pass and handed down, rather than recomputed
    /// for every token.
    private var maskedFlags: [Bool] { Masking.mask(verse, level: level) }

    var body: some View {
        let flags = maskedFlags
        let groups = LineWrapping.groupIndices(for: verse.tokens)
        FlowLayout(
            lineSpacing: metrics.lineSpacing,
            spaceWidth: metrics.spaceWidth,
            indentWidth: metrics.indentWidth
        ) {
            if isCarriedOver {
                // The one place the accent colour appears outside a blank: it
                // says "you already know this one" without a word of chrome.
                Text(Image(systemName: "checkmark"))
                    .font(Typography.verseNumber())
                    .foregroundStyle(Palette.blankUnderline)
                    .tokenSpaceBefore(false)
                    .tokenIndent(verse.indent)
                    // The mark and the number belong to the first word, so the
                    // line never breaks between a verse number and its verse.
                    .tokenGroup(groups.first ?? 0)
                    .accessibilityHidden(true)
            }
            if !verse.isSuperscription {
                verseNumber
                    .tokenSpaceBefore(isCarriedOver)
                    .tokenIndent(verse.indent)
                    .tokenGroup(groups.first ?? 0)
            }
            ForEach(Array(verse.tokens.enumerated()), id: \.offset) { index, token in
                tokenView(index: index, token: token, isMasked: flags[index])
                    .tokenGroup(groups[index])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Tokens

    @ViewBuilder
    private func tokenView(index: Int, token: Token, isMasked: Bool) -> some View {
        switch token.kind {
        case .lineBreak:
            Color.clear
                .frame(width: 0, height: 0)
                .tokenLineBreak(true, indent: token.indent ?? verse.indent)

        case .word:
            wordView(index: index, token: token, isMaskedAtLevel: isMasked)
                .tokenSpaceBefore(token.spaceBefore)
                .tokenIndent(verse.indent)

        case .punctuation, .selah:
            // §7.2 #4 and #5: structural scaffolding, always visible.
            Text(token.text)
                .font(font)
                .foregroundStyle(foreground)
                .tokenSpaceBefore(token.spaceBefore)
                .tokenIndent(verse.indent)
        }
    }

    @ViewBuilder
    private func wordView(index: Int, token: Token, isMaskedAtLevel: Bool) -> some View {
        let isMasked = isMaskedAtLevel && !peekedTokens.contains(index)
        let word = Text(token.text).font(font)

        word
            .foregroundStyle(foreground)
            // The glyphs stay in place and simply fade out, so the cross-fade
            // in §9 is a pure opacity change with no relayout.
            .opacity(isMasked ? 0 : 1)
            .background {
                blank(isVisible: isMasked)
            }
            .animation(Motion.crossFade(reduceMotion: reduceMotion), value: level)
            .animation(Motion.peekIn(reduceMotion: reduceMotion), value: peekedTokens.contains(index))
            // §12: expand the hit area beyond the visual bounds so short words
            // still make a usable target at small type sizes.
            .contentShape(Rectangle().inset(by: -8))
            .onTapGesture {
                guard isMaskedAtLevel, onPeek != nil else { return }
                peek(index: index)
            }
            .allowsHitTesting(onPeek != nil)
    }

    /// The blank: fill plus an underline rule. §12 — the fill is deliberately
    /// low contrast, so the underline is what keeps it perceivable. Never rely
    /// on the yellow alone.
    @ViewBuilder
    private func blank(isVisible: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.blankFill)
            Rectangle()
                .fill(Palette.blankUnderline)
                .frame(height: metrics.underlineThickness)
        }
        .opacity(isVisible ? 1 : 0)
    }

    // MARK: - Peek (§7.3)

    private func peek(index: Int) {
        onPeek?()
        withAnimation(Motion.peekIn(reduceMotion: reduceMotion)) {
            _ = peekedTokens.insert(index)
        }
        Task {
            try? await Task.sleep(for: .seconds(Motion.peekDuration))
            withAnimation(Motion.peekOut(reduceMotion: reduceMotion)) {
                _ = peekedTokens.remove(index)
            }
        }
    }

    // MARK: - Presentation

    private var verseNumber: some View {
        Text("\(verse.number)")
            .font(Typography.verseNumber())
            .foregroundStyle(Palette.verseNumber)
            .baselineOffset(metrics.verseNumberBaselineOffset)
            .accessibilityHidden(true)
    }

    private var font: Font {
        Typography.scripture(textStyle, italic: verse.isSuperscription)
    }

    private var foreground: Color {
        switch emphasis {
        case .active: return verse.isSuperscription ? Palette.dimmedText : Palette.text
        case .dimmed: return Palette.dimmedText
        }
    }

    /// §12: masked words announce as "blank"; the verse is one element.
    /// Built in `BibleCore` so the wording is unit tested.
    private var accessibilityLabel: String {
        let spoken = Masking.spokenText(verse, level: level)
        return isCarriedOver ? "Already memorized. \(spoken)" : spoken
    }

    private var metrics: ScriptureMetrics { ScriptureMetrics(textStyle: textStyle) }
}

/// Font measurements the flow layout needs. Recomputed whenever Dynamic Type
/// changes, because every value here scales with it.
struct ScriptureMetrics {
    let textStyle: Font.TextStyle

    private var uiFont: UIFont { ScriptureFont.uiFont(textStyle) }

    var spaceWidth: CGFloat { (" " as NSString).size(withAttributes: [.font: uiFont]).width }

    /// §9: generous line height, ~1.6× the font size.
    var lineSpacing: CGFloat { uiFont.pointSize * Typography.scriptureLineSpacingMultiple }

    var indentWidth: CGFloat { uiFont.pointSize * 1.1 }

    var underlineThickness: CGFloat { max(1, uiFont.pointSize / 12) }

    var verseNumberBaselineOffset: CGFloat { uiFont.pointSize * 0.28 }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
